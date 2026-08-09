library map_screen;

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart'
    as RideModel;
import 'package:ricardo/feature/models/socket/accept_ride_model.dart';
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

  List<LatLng> _fullRoutePoints = [];
  LatLng? _routeTarget;
  bool _isReFetchingRoute = false;

  BitmapDescriptor? customMarker;
  BitmapDescriptor? customCarMarker;
  BitmapDescriptor? customUserMarker;
  BitmapDescriptor? destinationMarker;

  double currentZoom = 18.5;
  bool _isLoading = true;
  bool _hasLocation = false;
  String _errorMessage = '';

  static const LatLng _defaultLocation = LatLng(37.7749, -122.4194);

  StreamSubscription<Position>? _positionStream;
  StreamSubscription<CompassEvent>? _compassStream;
  Position? _lastSentPosition;
  Position? _lastAcceptedPosition;
  bool _isTracking = false;
  DateTime? _lastHeadingUpdateAt;
  Timer? _currentMarkerAnimation;
  Timer? _remoteDriverAnimation;
  bool _isKeepingCarVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initMarkers();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await initializeMap();
      await loadStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: MapLoadingView());
    }

    if (!_hasLocation) {
      return Scaffold(
        body: MapErrorView(
          errorMessage: _errorMessage,
          onRetry: initializeMap,
        ),
      );
    }

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
            onMapCreated: (controller) {
              _mapController = controller;
            },
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
                  // onRideCancelled: () {
                  //   clearRideState();
                  // },
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

  Future<void> _ensureCarTravelVisible(
    LatLng currentPosition,
    LatLng targetPosition,
  ) async {
    final controller = _mapController;
    if (controller == null || _isKeepingCarVisible || !mounted) return;

    _isKeepingCarVisible = true;
    try {
      final bounds = await controller.getVisibleRegion();
      final latitudeMargin =
          (bounds.northeast.latitude - bounds.southwest.latitude).abs() * 0.2;
      final longitudeMargin =
          (bounds.northeast.longitude - bounds.southwest.longitude).abs() *
              0.15;
      final insideSafeArea = targetPosition.latitude >=
              bounds.southwest.latitude + latitudeMargin &&
          targetPosition.latitude <=
              bounds.northeast.latitude - latitudeMargin &&
          targetPosition.longitude >=
              bounds.southwest.longitude + longitudeMargin &&
          targetPosition.longitude <=
              bounds.northeast.longitude - longitudeMargin;

      if (!insideSafeArea) {
        var minLatitude =
            math.min(currentPosition.latitude, targetPosition.latitude);
        var maxLatitude =
            math.max(currentPosition.latitude, targetPosition.latitude);
        var minLongitude =
            math.min(currentPosition.longitude, targetPosition.longitude);
        var maxLongitude =
            math.max(currentPosition.longitude, targetPosition.longitude);
        if ((maxLatitude - minLatitude).abs() < 0.00001) {
          minLatitude -= 0.00001;
          maxLatitude += 0.00001;
        }
        if ((maxLongitude - minLongitude).abs() < 0.00001) {
          minLongitude -= 0.00001;
          maxLongitude += 0.00001;
        }

        mapOPTController.hideLocationButton();
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(minLatitude, minLongitude),
              northeast: LatLng(maxLatitude, maxLongitude),
            ),
            48,
          ),
        );
      }
    } finally {
      _isKeepingCarVisible = false;
    }
  }

  @override
  void dispose() {
    _currentMarkerAnimation?.cancel();
    _remoteDriverAnimation?.cancel();
    _mapController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    positionStream?.cancel();
    disconnectSocket();
    stopLocationTracking();
    super.dispose();
  }
}
