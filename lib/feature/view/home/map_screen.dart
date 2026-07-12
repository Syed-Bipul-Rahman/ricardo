library map_screen;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart' as RideModel;
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
            onCameraMove: (_) {
              // Show the location button whenever the user pans/zooms the map,
              // exactly like Uber does.
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
                  onRideCancelled: () {
                    clearRideState();
                  },
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
    // Hide the button immediately — it reappears only when the map moves again.
    mapOPTController.hideLocationButton();

    _mapController?.animateCamera(
      duration: const Duration(seconds: 2),
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            mapOPTController.currentLatitudePosition!.value,
            mapOPTController.currentLongitudePosition!.value,
          ),
          zoom: currentZoom, // restore the default zoom level too
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
