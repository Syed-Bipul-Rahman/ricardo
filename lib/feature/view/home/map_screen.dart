library map_screen;

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart'
    as RideModel;
import 'package:ricardo/feature/models/socket/accept_ride_model.dart';
import 'package:ricardo/app/helpers/screen_awake_helper.dart';
import 'package:ricardo/feature/view/home/map/helpers/live_driver_location_tracker.dart';
import 'package:ricardo/feature/view/home/map/helpers/vehicle_motion_engine.dart';
import 'link_export_file.dart';

part 'map/parts/_bootstrap.part.dart';
part 'map/parts/_markers.part.dart';
part 'map/parts/_routes.part.dart';
part 'map/parts/_sockets.part.dart';
part 'map/parts/_tracking.part.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  final userController = Get.find<UserController>();
  final googleSearchLocationController =
      Get.find<GoogleSearchLocationController>();
  final rideController = Get.find<RideController>();
  final mapOPTController = Get.find<MapOPTController>();

  GoogleMapController? _mapController;
  Set<Marker> markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> polylineCoordinates = [];
  StreamSubscription<Position>? positionStream;

  /// Full driving-route geometry (immutable until refetch). Never trim this —
  /// trimming destroyed turn vertices and let the car cut corners / footpaths.
  List<LatLng> _fullRoutePoints = [];

  /// Forward progress cursor into [_fullRoutePoints] so snaps prefer the road
  /// ahead through turns instead of a nearer sidewalk-side segment behind.
  int _routeProgressIndex = 0;
  LatLng? _routeTarget;
  bool _isReFetchingRoute = false;
  int _routeGeneration = 0;
  DateTime? _lastAnimatedRouteUpdateAt;

  BitmapDescriptor? customMarker;
  BitmapDescriptor? customCarMarker;
  BitmapDescriptor? customUserMarker;
  BitmapDescriptor? destinationMarker;

  double currentZoom = 18.5;
  bool _isLoading = false;
  bool _hasLocation = true;
  String _errorMessage = '';

  final LatLng _defaultLocation = const LatLng(
    kMapFallbackLatitude,
    kMapFallbackLongitude,
  );

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  Position? _lastSentPosition;
  DateTime? _lastLocationSentAt;
  bool _isTracking = false;
  DateTime? _lastHeadingUpdateAt;
  LatLng? _remoteDriverTarget;
  final LiveDriverLocationTracker _liveDriverTracker =
      LiveDriverLocationTracker();
  final VehicleMotionEngine _selfMotionEngine =
      VehicleMotionEngine(smoothObservedSpeed: true);
  final VehicleMotionEngine _remoteMotionEngine =
      VehicleMotionEngine(smoothObservedSpeed: false);
  bool _isKeepingCarVisible = false;
  DateTime? _lastCarTravelCameraAt;
  LatLng? _pendingCameraTarget;
  // Toggle live location pipeline diagnostics in debug consoles.
  final bool _liveLocationDiag = false;
  DateTime? _lastMarkerRenderLogAt;
  Worker? _screenAwakeWorker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initMarkers();
    _bindVehicleMotionEngines();
    _bindScreenAwake();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initializeMap();
      await loadStatus();
      _syncScreenAwake();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Always keep GoogleMap mounted — never replace it with a loading/error page.
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          MapView(
            mapOPTController: mapOPTController,
            currentZoom: currentZoom,
            defaultLocation: _defaultLocation,
            markersBuilder: buildMarkers,
            polylines: _polylines,
            onMapCreated: _onMapCreated,
            onCameraMove: (_) {
              mapOPTController.notifyMapMoved();
            },
          ),
          ...buildPassengerOverlays(
            userController: userController,
            googleSearchLocationController: googleSearchLocationController,
            rideController: rideController,
            mapOPTController: mapOPTController,
          ),
          SafeArea(
            child: Column(
              children: [
                DriverTopSection(
                  userController: userController,
                  rideController: rideController,
                  mapOPTController: mapOPTController,
                ),
                const Spacer(),
                SwipeToSearchButton(
                  userController: userController,
                  googleSearchLocationController:
                      googleSearchLocationController,
                  rideController: rideController,
                  mapOPTController: mapOPTController,
                ),
                DriverBottomPanel(
                  userController: userController,
                  rideController: rideController,
                  mapOPTController: mapOPTController,
                  onRideCancelled: () => finishRide(),
                ),
              ],
            ),
          ),
          const LocationStatusBanner(),
          DraggableLocationShowButton(
            mapOPTController: mapOPTController,
            onTap: moveToCurrentLocation,
          )
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncScreenAwake(lifecycle: state);

    if (state != AppLifecycleState.resumed) return;
    if (!mapOPTController.hasValidCoordinates) {
      unawaited(getCurrentLocation());
    } else {
      unawaited(mapOPTController.maybeRefreshAddress());
    }
  }

  void _bindScreenAwake() {
    final sources = <RxInterface<dynamic>>[
      mapOPTController.rideStatusData,
      rideController.isRideAccepted,
    ];
    if (Get.isRegistered<CustomBottomNavBarController>()) {
      sources.add(Get.find<CustomBottomNavBarController>().selectedIndex);
    }
    _screenAwakeWorker = everAll(sources, (_) => _syncScreenAwake());
    _syncScreenAwake();
  }

  /// Screen stays awake only while this tracking view is in the foreground
  /// during an active ride. Leaving the tab, backgrounding, or ending the
  /// ride restores the system timeout.
  void _syncScreenAwake({AppLifecycleState? lifecycle}) {
    if (!mounted) {
      unawaited(ScreenAwakeHelper.release());
      return;
    }

    final state = lifecycle ?? WidgetsBinding.instance.lifecycleState;
    final inForeground = state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;

    var onTrackingTab = true;
    if (Get.isRegistered<CustomBottomNavBarController>()) {
      onTrackingTab =
          Get.find<CustomBottomNavBarController>().selectedIndex.value == 0;
    }

    final trackingActive = mapOPTController.isInActiveRide ||
        rideController.isRideAccepted.value == true;

    unawaited(
      ScreenAwakeHelper.setDesired(
        trackingActive && onTrackingTab && inForeground,
      ),
    );
  }

  void moveToCurrentLocation() {
    mapOPTController.hideLocationButton();

    _mapController?.animateCamera(
      duration: const Duration(seconds: 2),
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            mapOPTController.currentLatitudePosition!.value,
            mapOPTController.currentLongitudePosition!.value,
          ),
          zoom: currentZoom,
          bearing: 0,
          tilt: 0,
        ),
      ),
    );
  }

  /// Keep the live car on-screen without zoom jumps.
  ///
  /// Uber/Pathao passenger style: **north always up** (`bearing: 0`). The car
  /// icon rotates on the road; the map does not spin. Fitting a tiny
  /// start→target LatLngBounds used to zoom wildly and make the marker look
  /// like it was flying across the screen — we only pan at a stable zoom.
  Future<void> _ensureCarTravelVisible(
    LatLng currentPosition,
    LatLng targetPosition,
  ) async {
    final controller = _mapController;
    if (controller == null || _isKeepingCarVisible || !mounted) return;
    if (!mapOPTController.isInActiveRide) return;
    // User panned/zoomed — do not steal the camera from marker motion.
    if (mapOPTController.isLocationButtonVisible.value) return;

    final now = DateTime.now();
    final last = _lastCarTravelCameraAt;
    // Throttle tile churn; still responsive enough to follow turns.
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 750)) {
      return;
    }

    _isKeepingCarVisible = true;
    try {
      final bounds = await controller.getVisibleRegion();
      final latitudeMargin =
          (bounds.northeast.latitude - bounds.southwest.latitude).abs() * 0.28;
      final longitudeMargin =
          (bounds.northeast.longitude - bounds.southwest.longitude).abs() *
              0.28;
      final insideSafeArea = targetPosition.latitude >=
              bounds.southwest.latitude + latitudeMargin &&
          targetPosition.latitude <=
              bounds.northeast.latitude - latitudeMargin &&
          targetPosition.longitude >=
              bounds.southwest.longitude + longitudeMargin &&
          targetPosition.longitude <=
              bounds.northeast.longitude - longitudeMargin;

      if (!insideSafeArea) {
        _lastCarTravelCameraAt = now;
        mapOPTController.hideLocationButton();
        // Pan only — same zoom, north-up. Never bounds-fit two GPS points.
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: targetPosition,
              zoom: currentZoom,
              bearing: 0,
              tilt: 0,
            ),
          ),
        );
      }
    } finally {
      _isKeepingCarVisible = false;
    }
  }

  @override
  void dispose() {
    _screenAwakeWorker?.dispose();
    _screenAwakeWorker = null;
    unawaited(ScreenAwakeHelper.release());
    _selfMotionEngine.dispose();
    _remoteMotionEngine.dispose();
    _mapController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    positionStream?.cancel();
    disconnectSocket();
    stopLocationTracking();
    super.dispose();
  }
}
