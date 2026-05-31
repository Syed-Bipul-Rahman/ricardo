library map_screen;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart'
    as RideModel;
import 'package:ricardo/feature/models/socket/accept_ride_driver_model.dart';
import 'package:ricardo/feature/models/socket/accept_ride_model.dart';
import 'package:ricardo/feature/models/socket/get_ride_driver_location.dart';
import 'package:ricardo/feature/view/home/map/dialogs/driver_info_dialog.dart';
import 'package:ricardo/feature/view/home/map/dialogs/permission_dialogs.dart';
import 'package:ricardo/feature/view/home/map/driver_location_service.dart';
import 'package:ricardo/feature/view/home/map/helpers/location_bootstrap_helper.dart';
import 'package:ricardo/feature/view/home/map/widgets/driver_bottom_panel.dart';
import 'package:ricardo/feature/view/home/map/widgets/driver_top_section.dart';
import 'package:ricardo/feature/view/home/map/widgets/location_status_banner.dart';
import 'package:ricardo/feature/view/home/map/widgets/map_error_view.dart';
import 'package:ricardo/feature/view/home/map/widgets/map_loading_view.dart';
import 'package:ricardo/feature/view/home/map/widgets/map_view.dart';
import 'package:ricardo/feature/view/home/map/widgets/passenger_overlays.dart';
import 'package:ricardo/feature/view/home/map/widgets/swipe_to_search_button.dart';
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
  bool _isTracking = false;

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
                  onRideCancelled: () {
                    _polylines.clear();
                    buildMarkers().clear();
                  },
                ),
              ],
            ),
          ),
          const LocationStatusBanner(),
          Obx(
            () => Positioned(
              top: mapOPTController.buttonTop.value,
              right: mapOPTController.buttonRight.value,
              child: GestureDetector(
                onPanUpdate: (details) {
                  final size = MediaQuery.of(context).size;

                  const buttonSize = 56.0;
                  const topPadding = 80.0;
                  const bottomPadding = 180.0;

                  final newTop =
                      mapOPTController.buttonTop.value + details.delta.dy;

                  final newRight =
                      mapOPTController.buttonRight.value - details.delta.dx;

                  mapOPTController.buttonTop.value = newTop.clamp(
                    topPadding,
                    size.height - bottomPadding,
                  );

                  mapOPTController.buttonRight.value = newRight.clamp(
                    10.0,
                    size.width - buttonSize - 10,
                  );
                },
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(30),
                  color: Colors.white,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: moveToCurrentLocation,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(
                        Icons.my_location,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void moveToCurrentLocation() {
    _mapController?.animateCamera(
      duration: Duration(seconds: 3),
      CameraUpdate.newLatLng(
        LatLng(
          mapOPTController.currentLatitudePosition!.value,
          mapOPTController.currentLongitudePosition!.value,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    positionStream?.cancel();
    disconnectSocket();
    stopLocationTracking();
    super.dispose();
  }
}
