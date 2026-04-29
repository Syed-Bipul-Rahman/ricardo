import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart'
    as RideModel;
import 'package:ricardo/feature/models/socket/accept_ride_driver_model.dart';
import 'package:ricardo/feature/models/socket/accept_ride_model.dart';
import 'package:ricardo/feature/models/socket/get_ride_driver_location.dart';
import 'package:ricardo/feature/view/home/map/driver_location_service.dart';
import 'package:ricardo/feature/view/home/map/location_disable_banner_widget.dart';
import 'package:ricardo/widgets/custom_loader.dart';
import 'link_export_file.dart';

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

  // Full route points for live polyline trimming (driver side)
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
  LatLng? _currentPosition;

  static const LatLng _defaultLocation = LatLng(37.7749, -122.4194);

  // ─────────────────────────────────────────────────────────
  // INIT STATE
  // ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initMarkers();

    // ✅ Everything deferred to post-frame so no layout-during-layout crash
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeMap();
      await loadStatus();
      // _setupSocketReconnection();
    });

    // ever(rideController.isRideAccepted, (bool accepted) {
    //   if (accepted == true) _loadRoute();
    // });
  }

  // ─────────────────────────────────────────────────────────
  // LOAD STATUS (called once after first frame)
  // ─────────────────────────────────────────────────────────
  Future<void> loadStatus() async {
    final bool? data = await userController.fetchActiveRideStatus();
    if (data == true) {
      final rideStatus = mapOPTController.rideStatusData.value;
      if (rideStatus != null &&
          (rideStatus.acceptRide == true ||
              rideStatus.ongoingRide == true ||
              rideStatus.arrivingRide == true)) {
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  // CLEAR RIDE STATE (DRY helper)
  // ─────────────────────────────────────────────────────────
  void _clearRideState() {
    rideController.isRideAccepted.value = false;
    rideController.acceptRideModel.value = null;
    mapOPTController.acceptedRideDriverDataStatus.value = false;
    mapOPTController.acceptedRideDriverData.value = null;
    mapOPTController.isPassengerRequest.value = false;
    mapOPTController.rideStatusData.value = null;
    mapOPTController.rideRequestReceivedAt.value = null;
    PrefsHelper.setString('status', '');
    PrefsHelper.setString('ride-accepted-data', '');
    PrefsHelper.setString('driver-status', '');
    PrefsHelper.setString('ride-accepted-driver-data', '');
  }

  // ─────────────────────────────────────────────────────────
  // LOAD ROUTE (passenger accepted view)
  // ─────────────────────────────────────────────────────────
  /*Future<void> _loadRoute() async {
    try {
      final acceptedRide = mapOPTController.rideStatusData.value;
      if (acceptedRide == null) return;

      final pickupCoords = acceptedRide.ride?.pickupLocation?.coordinates;
      final destCoords = acceptedRide.ride?.destinationLocation?.coordinates;
      final driverAcceptedLocationCoords =
          acceptedRide.ride?.driverAcceptedLocation?.coordinates;

      final LatLng origin = (pickupCoords != null && pickupCoords.length == 2)
          ? LatLng(pickupCoords[1], pickupCoords[0])
          : LatLng(
        googleSearchLocationController.selectedPickup.value?.lat ?? 0.0,
        googleSearchLocationController.selectedPickup.value?.lng ?? 0.0,
      );

      final LatLng dest = (destCoords != null && destCoords.length == 2)
          ? LatLng(destCoords[1], destCoords[0])
          : LatLng(
        googleSearchLocationController.selectedDrop.value?.lat ?? 0.0,
        googleSearchLocationController.selectedDrop.value?.lng ?? 0.0,
      );

      final LatLng acceptedLocation = (driverAcceptedLocationCoords != null &&
          driverAcceptedLocationCoords.length == 2)
          ? LatLng(
          driverAcceptedLocationCoords[1], driverAcceptedLocationCoords[0])
          : LatLng(
        googleSearchLocationController.selectedDrop.value?.lat ?? 0.0,
        googleSearchLocationController.selectedDrop.value?.lng ?? 0.0,
      );

      if (origin.latitude == 0.0 || dest.latitude == 0.0) {
        debugPrint('Skipping route — coords not ready');
        return;
      }

      final List<LatLng> point =
      await DirectionsService.getPolyline(acceptedLocation, origin);
      final List<LatLng> points =
      await DirectionsService.getPolyline(origin, dest);

      if (points.isEmpty) {
        Get.snackbar('Error', 'Could not load route. Please check your API key.');
        return;
      }

      if (!mounted) return;
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('Driver-Current-Location'),
            points: point,
            color: Colors.blue,
            width: 8,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            patterns: [PatternItem.dot, PatternItem.gap(12)],
          ),
        };

        markers.removeWhere((m) =>
        m.markerId.value == 'current-location' ||
            m.markerId.value == 'Pick-Up-Location');

        markers.addAll({
          Marker(
            markerId: const MarkerId('Pick-Up-Location'),
            position: origin,
            icon: BitmapDescriptor.defaultMarker,
          ),
        });
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final bounds = _boundsFromLatLng(points);
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }*/

  // ─────────────────────────────────────────────────────────
  // LOAD ACCEPTED RIDE ROUTE (driver view)
  // ─────────────────────────────────────────────────────────
  Future<void> _loadAcceptedRideRoute() async {
    try {
      final acceptedRide = mapOPTController.rideStatusData.value;
      if (acceptedRide == null) return;

      final Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final LatLng driverLocation = LatLng(
        currentPosition.latitude,
        currentPosition.longitude,
      );

      final pickupCoords = acceptedRide.ride?.pickupLocation?.coordinates;
      if (pickupCoords == null || pickupCoords.length < 2) return;
      final LatLng pickupLocation = LatLng(pickupCoords[1], pickupCoords[0]);

      if (driverLocation.latitude == 0.0 || pickupLocation.latitude == 0.0) {
        debugPrint('Skipping — coords not ready');
        return;
      }

      final bool arrive = acceptedRide.arrivingRide == true;
      final bool onGoingRide = acceptedRide.ongoingRide == true;

      List<LatLng> activeRoutePoints = [];

      if (arrive || onGoingRide) {
        activeRoutePoints = await DirectionsService.getPolyline(
          driverLocation,
          pickupLocation,
        );
      }
      if (activeRoutePoints.isEmpty) return;

      _fullRoutePoints = List.from(activeRoutePoints);
      if (arrive || onGoingRide) {
        _routeTarget = pickupLocation;
      }

      if (!mounted) return;
      setState(() {
        _polylines.clear();

        markers.removeWhere((m) =>
            m.markerId.value == 'driver_location' ||
            m.markerId.value == 'pickup_location');
        if (arrive || onGoingRide) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('driver_to_pickup'),
              points: activeRoutePoints,
              color: Colors.black87,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
          final isPassenger =
              userController.userModel.value?.userProfile?.role ==
                  AppConstants.passenger;
          markers.add(
            Marker(
              markerId: const MarkerId('pickup_location'),
              position: pickupLocation,
              icon: (isPassenger && customUserMarker != null)
                  ? customMarker!
                  : customUserMarker!,
            ),
          );
        }
      });

      final bounds = _boundsFromLatLng(activeRoutePoints);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } catch (e) {
      debugPrint('_loadAcceptedRideRoute error: $e');
    }
  }

  Future<void> _pickupToDestinationRoute() async {
    try {
      final acceptedRide = mapOPTController.rideStatusData.value;
      if (acceptedRide == null) return;

      final Position currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final LatLng driverLocation = LatLng(
        currentPosition.latitude,
        currentPosition.longitude,
      );

      final destinationCoords =
          acceptedRide.ride?.destinationLocation?.coordinates;
      if (destinationCoords == null || destinationCoords.length < 2) return;
      final LatLng destinationLocation =
          LatLng(destinationCoords[1], destinationCoords[0]);

      if (driverLocation.latitude == 0.0 ||
          destinationLocation.latitude == 0.0) {
        debugPrint('Skipping — coords not ready');
        return;
      }

      final bool startRide = acceptedRide.startRide == true;
      final bool completeRide = acceptedRide.completeRide == true;

      List<LatLng> activeRoutePoints = [];

      if (startRide || completeRide) {
        activeRoutePoints = await DirectionsService.getPolyline(
          driverLocation,
          destinationLocation,
        );
      }
      if (activeRoutePoints.isEmpty) return;

      _fullRoutePoints = List.from(activeRoutePoints);
      if (startRide || completeRide) {
        _routeTarget = destinationLocation;
      }

      if (!mounted) return;
      setState(() {
        _polylines.clear();

        markers.removeWhere((m) =>
            m.markerId.value == 'driver_location' ||
            m.markerId.value == 'pickup_location');
        if (startRide || completeRide) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('driver_to_destination'),
              points: activeRoutePoints,
              color: Colors.black87,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
          final isPassenger =
              userController.userModel.value?.userProfile?.role ==
                  AppConstants.passenger;
          markers.add(
            Marker(
              markerId: const MarkerId('pickup_location'),
              position: destinationLocation,
              icon: (isPassenger && customUserMarker != null)
                  ? customMarker!
                  : destinationMarker!,
            ),
          );
        }
      });

      final bounds = _boundsFromLatLng(activeRoutePoints);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } catch (e) {
      debugPrint('_loadAcceptedRideRoute error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // LIVE POLYLINE TRIMMING
  // ─────────────────────────────────────────────────────────
  void _updatePolylineForDriverPosition(LatLng driverPos) {
    if (_fullRoutePoints.isEmpty || _routeTarget == null) return;

    int closestIndex = 0;
    double closestDist = double.infinity;
    for (int i = 0; i < _fullRoutePoints.length; i++) {
      final d = Geolocator.distanceBetween(
        driverPos.latitude,
        driverPos.longitude,
        _fullRoutePoints[i].latitude,
        _fullRoutePoints[i].longitude,
      );
      if (d < closestDist) {
        closestDist = d;
        closestIndex = i;
      }
    }

    if (closestDist > 50 && !_isReFetchingRoute) {
      _isReFetchingRoute = true;
      _reFetchRouteFromDriver(driverPos);
      return;
    }

    final trimmed = _fullRoutePoints.sublist(closestIndex);
    final updatedPoints = [driverPos, ...trimmed];
    _fullRoutePoints = trimmed;

    if (!mounted) return;
    setState(() {
      _polylines.removeWhere((p) =>
          p.polylineId.value == 'driver_to_pickup' ||
          p.polylineId.value == 'pickup_to_destination');

      final rideStatus = mapOPTController.rideStatusData.value;
      final bool isPickupPhase =
          rideStatus?.acceptRide == true || rideStatus?.ongoingRide == true;

      _polylines.add(
        Polyline(
          polylineId: PolylineId(
              isPickupPhase ? 'driver_to_pickup' : 'pickup_to_destination'),
          points: updatedPoints,
          color: isPickupPhase ? Colors.black87 : Colors.green,
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    });
  }

  Future<void> _reFetchRouteFromDriver(LatLng driverPos) async {
    try {
      if (_routeTarget == null) return;
      final newRoute =
          await DirectionsService.getPolyline(driverPos, _routeTarget!);
      if (newRoute.isNotEmpty) {
        _fullRoutePoints = newRoute;
        _updatePolylineForDriverPosition(driverPos);
      }
    } catch (e) {
      debugPrint('_reFetchRouteFromDriver error: $e');
    } finally {
      _isReFetchingRoute = false;
    }
  }

  LatLngBounds _boundsFromLatLng(List<LatLng> points) {
    double? minLat, minLng, maxLat, maxLng;
    for (var point in points) {
      minLat = minLat == null
          ? point.latitude
          : minLat < point.latitude
              ? minLat
              : point.latitude;
      minLng = minLng == null
          ? point.longitude
          : minLng < point.longitude
              ? minLng
              : point.longitude;
      maxLat = maxLat == null
          ? point.latitude
          : maxLat > point.latitude
              ? maxLat
              : point.latitude;
      maxLng = maxLng == null
          ? point.longitude
          : maxLng > point.longitude
              ? maxLng
              : point.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD MARKERS
  // ─────────────────────────────────────────────────────────
  Set<Marker> _buildMarkers() {
    final Set<Marker> result = {};

    final currentLat = _currentPosition?.latitude ?? 0.0;
    final currentLng = _currentPosition?.longitude ?? 0.0;
    final rideStatus = mapOPTController.rideStatusData.value;

    if (currentLat != 0.0 && currentLng != 0.0) {
      if (rideStatus?.acceptRide == true ||
          rideStatus?.ongoingRide == true ||
          rideStatus?.arrivingRide == true ||
          rideStatus?.startRide == true ||
          rideStatus?.completeRide == true) {
        result.add(
          Marker(
            markerId: const MarkerId('currentPassenger'),
            position: LatLng(currentLat, currentLng),
            icon: customCarMarker ?? BitmapDescriptor.defaultMarker,
            // icon: userController.userModel.value?.userProfile?.role ==
            //     AppConstants.passenger
            //     ? customMarker ?? BitmapDescriptor.defaultMarker
            //     : customCarMarker ?? BitmapDescriptor.defaultMarker,
          ),
        );
      } else {
        result.add(
          Marker(
            markerId: const MarkerId('currentPassenger'),
            position: LatLng(currentLat, currentLng),
            // icon: customCarMarker ?? BitmapDescriptor.defaultMarker,
            icon: userController.userModel.value?.userProfile?.role ==
                    AppConstants.passenger
                ? customMarker ?? BitmapDescriptor.defaultMarker
                : customCarMarker ?? BitmapDescriptor.defaultMarker,
          ),
        );
      }
    }

    for (final m in markers) {
      if (m.markerId.value != 'currentPassenger') {
        result.add(m);
      }
    }

    final bool isRouteActive = markers.any(
      (m) =>
          m.markerId.value == 'Pick-Up-Location' ||
          m.markerId.value == 'Destination' ||
          m.markerId.value == 'pickup_location' ||
          m.markerId.value == 'destination_location',
    );

    final bool showDriverIcons =
        rideController.viewInMapReturn.value || !isRouteActive;

    if (showDriverIcons) {
      final drivers = rideController.drivers;
      for (var driver in drivers) {
        final coords = driver.location?.coordinates;
        if (coords != null && coords.length == 2) {
          result.add(Marker(
            markerId: MarkerId(driver.sId ?? UniqueKey().toString()),
            position: LatLng(coords[1], coords[0]),
            icon: customCarMarker ?? BitmapDescriptor.defaultMarker,
            onTap: () => _showDriverDialog(driver),
          ));
        }
      }
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────
  // INIT MARKERS
  // ─────────────────────────────────────────────────────────
  Future<void> _initMarkers() async {
    customMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      "assets/images/passenger_location_marker.png",
    );
    customCarMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      "assets/images/car_marker.png",
    );
    customUserMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      'assets/images/passenger_marker.png',
    );
    destinationMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      'assets/images/destination_marker.png',
    );
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────
  // INITIALIZE MAP
  // ─────────────────────────────────────────────────────────
  Future<void> _initializeMap() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      bool hasPermission = await _requestLocationPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Location permission is required to use this app';
        });
        return;
      }

      await _getCurrentLocation();
      await connectSocket();
      await userController.fetchUser();
      await _loadAcceptedRideRoute();
    } catch (e) {
      debugPrint('_initializeMap error: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // PERMISSIONS
  // ─────────────────────────────────────────────────────────
  Future<bool> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showPermissionDeniedDialog();
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showPermissionPermanentlyDeniedDialog();
      return false;
    }

    return true;
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'This app needs location access to show your position on the map and find nearby rides.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initializeMap();
            },
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPermissionPermanentlyDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'Location permission is permanently denied. Please enable it in settings to use this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // GET CURRENT LOCATION
  // ─────────────────────────────────────────────────────────
  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));

      mapOPTController.currentLatitudePosition?.value = position.latitude;
      mapOPTController.currentLongitudePosition?.value = position.longitude;

      await mapOPTController.getLocation();

      if (!mounted) return;
      setState(() {
        _hasLocation = true;
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      _startLocationTracking();

      if (_mapController != null) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: currentZoom,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not get your location. Using default location.';
        _hasLocation = true;
        _currentPosition ??= _defaultLocation;
      });
    }
  }

  // ─────────────────────────────────────────────────────────
  // CONNECT SOCKET
  // ─────────────────────────────────────────────────────────
  Future<void> connectSocket() async {
    try {
      final String? fcmToken = await FirebaseNotificationService.getFCMToken();
      if (fcmToken != null) {
        await PrefsHelper.setString(AppConstants.fcmToken, fcmToken);
      }
    } catch (e) {
      debugPrint('connectSocket FCM token error: $e');
    }

    // New ride request
    SocketServices.socket?.on('new-ride-request', (data) {
      if (data['newRideRequest'] == true) {
        mapOPTController.startRideRequestTimer();
        mapOPTController.isPassengerRequest.value = true;
        mapOPTController.rideDetailsData.value =
            RideDetailsSocketModel.fromJson(data['rideDetails']);
      }
    });

    // Cancel ride request
    SocketServices.socket?.on('cancel-ride-request', (data) {
      if (data['isCancelPickRequest'] == true) {
        mapOPTController.isPassengerRequest.value = false;
        mapOPTController.cancelRideRequestTimer();
      }
    });

    // Ride accepted (passenger side)
    SocketServices.socket?.on('ride-accepted', (data) {
      if (data is! Map<String, dynamic>) return;
      if (data['isRideAccepted'] != true) return;

      final driver = data['driver'];
      rideController.isRideAccepted.value = true;
      rideController.acceptedRideDriverName.value =
          (driver is Map ? driver['driverName'] : null) ?? '';

      try {
        rideController.acceptRideModel.value = AcceptRideModel.fromJson(data);
      } catch (e) {
        debugPrint('ride-accepted parse error: $e');
      }
    });

    // Ride accepted (driver side)
    SocketServices.socket?.on('ride-accepted-driver', (data) {
      if (data is Map<String, dynamic>) {
        if (data['isRideAcceptedDriver'] == true) {
          mapOPTController.acceptedRideDriverDataStatus.value = true;
          mapOPTController.acceptedRideDriverData.value =
              AcceptRideDriverModel.fromJson(data);
        }
      }
    });

    // ✅ get-ride-driver-location — single listener here only
    SocketServices.socket?.off('get-ride-driver-location');
    SocketServices.socket?.on('get-ride-driver-location', (data) {
      try {
        Map<String, dynamic> jsonData;
        if (data is List) {
          jsonData = Map<String, dynamic>.from(data[0]);
        } else if (data is String) {
          jsonData = jsonDecode(data);
        } else if (data is Map) {
          jsonData = Map<String, dynamic>.from(data);
        } else {
          return;
        }
        mapOPTController.getRideDriverLocation.value =
            GetRideDriverLocation.fromJson(jsonData);
        mapOPTController.getRideDriverLocation.refresh(); // ✅ force Obx update
        debugPrint('📍 Driver location updated ');
      } catch (e) {
        debugPrint('get-ride-driver-location error: $e');
      }
    });

    SocketServices.socket?.on('ride-status', (data) async {
      try {
        Map<String, dynamic> jsonData;
        if (data is List) {
          jsonData = Map<String, dynamic>.from(data[0]);
        } else if (data is String) {
          jsonData = jsonDecode(data);
        } else if (data is Map) {
          jsonData = Map<String, dynamic>.from(data);
        } else {
          return;
        }

        final RideModel.RideStatusModel rideStatus =
            RideModel.RideStatusModel.fromJson(jsonData);

        mapOPTController.rideStatusData.value = rideStatus;

        if (rideStatus.acceptRide == true) {
          rideController.drivers.clear();
          mapOPTController.isCurrentMarkerShowOrNot.value = true;
        } else if (rideStatus.ongoingRide == true) {
          _loadAcceptedRideRoute();
        } else if (rideStatus.arrivingRide == true) {
          markers.clear();
          _polylines.clear();
        } else if (rideStatus.startRide == true) {
          _pickupToDestinationRoute();
          // _clearRideState();
          // SocketServices.socket?.off('ride-status');
        } else if (rideStatus.driverCancel == true ||
            rideStatus.passengerCancel == true) {
          debugPrint('❌ ride-status: Ride cancelled');
          _clearRideState();
          SocketServices.socket?.off('ride-status');
        }
        print('come there==========================');
        // SocketServices.socket?.emit('get-driver-location', {'rideId': rideStatus.ride!.id!});
        DriverLocationService().stop();
        DriverLocationService().startEmitting(rideStatus.ride!.id!);

        await mapOPTController.driverServiceFun();
      } catch (e, stackTrace) {
        debugPrint('ride-status ERROR: $e');
        debugPrint('STACK: $stackTrace');
      }
    });
  }

  // ─────────────────────────────────────────────────────────
  // LOCATION TRACKING (every 3 seconds)
  // ─────────────────────────────────────────────────────────
  Timer? _locationTimer;
  bool _isTracking = false;

  void _startLocationTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    String? token = await PrefsHelper.getString(AppConstants.bearerToken);

    _locationTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        LatLng newLocation = LatLng(position.latitude, position.longitude);

        mapOPTController.currentLatitudePosition?.value = position.latitude;
        mapOPTController.currentLongitudePosition?.value = position.longitude;

        if (mounted) {
          setState(() {
            _currentPosition = newLocation;
          });
        }

        SocketServices.socket?.emit('update-user-location', {
          "accessToken": token,
          "location": {
            "type": "Point",
            "coordinates": [newLocation.longitude, newLocation.latitude]
          }
        });

        final rideStatus = mapOPTController.rideStatusData.value;
        if (rideStatus != null &&
            (rideStatus.acceptRide == true ||
                rideStatus.ongoingRide == true ||
                rideStatus.arrivingRide == true || rideStatus.startRide == true || rideStatus.completeRide == true ) ) {
          _updatePolylineForDriverPosition(newLocation);
        }

        if (_mapController != null && mounted) {
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: newLocation, zoom: currentZoom),
            ),
          );
        }
      } catch (error) {
        debugPrint('Location error: $error');
      }
    });
  }

  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _isTracking = false;
    positionStream?.cancel();
  }

  // ─────────────────────────────────────────────────────────
  // DRIVER DIALOG
  // ─────────────────────────────────────────────────────────
  void _showDriverDialog(driver) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.darkColor.withValues(alpha: 0.15),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      driver.image != null && driver.image!.isNotEmpty
                          ? ClipRRect(
                              clipBehavior: Clip.antiAlias,
                              borderRadius: BorderRadius.circular(50),
                              child: Image.network(
                                '${ApiUrls.imageBaseUrl}${driver.image}',
                                fit: BoxFit.cover,
                                height: 60,
                                width: 60,
                                errorBuilder: (context, error, stackTrace) =>
                                    Image.asset('assets/images/driver.png',
                                        height: 60,
                                        width: 60,
                                        fit: BoxFit.cover),
                              ),
                            )
                          : CircleAvatar(
                              radius: 30,
                              child: Image.asset('assets/images/driver.png',
                                  height: 60, width: 60, fit: BoxFit.cover),
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${driver.name}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    color: Colors.amber, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                    '${driver.rating} (${driver.totalRatings})'),
                                const SizedBox(width: 8),
                                const Text('|'),
                                const SizedBox(width: 8),
                                Text('${driver.trips} Trips'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.phone,
                                    color: Colors.green, size: 16),
                                const SizedBox(width: 4),
                                Text('${driver.phone}'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          launchUrl(Uri.parse("tel:${driver.phone}"));
                        },
                        child: RepaintBoundary(
                          // ✅ isolates rendering
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.whiteColor,
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: SvgPicture.asset(
                              Assets.icons.driverCardPhone,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Align(
                    alignment: Alignment.center,
                    child: Text('Car Info.',
                        style: TextStyle(
                            color: Colors.grey, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${driver.vehicle?.carName}',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('${driver.vehicle?.numberOfSeat} Seat'),
                            const SizedBox(height: 4),
                            Text('${driver.vehicle?.carPlateNumber}'),
                            const SizedBox(height: 4),
                            FutureBuilder<String>(
                              future: DirectionsService.calculateDistance(
                                driver.location?.coordinates?[0],
                                driver.location?.coordinates?[1],
                              ),
                              builder: (context, snapshot) {
                                final distanceText =
                                    snapshot.data ?? 'Calculating...';
                                return Text(
                                  '$distanceText away from you.',
                                  overflow: TextOverflow.ellipsis,
                                  // ✅ safety for long text
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontFamily: FontFamily.poppins,
                                    fontSize: 16.sp,
                                    color: AppColors.dottedBorderColor,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: driver.image != null && driver.image!.isNotEmpty
                            ? Image.network(
                                '${ApiUrls.imageBaseUrl}${driver.image}',
                                width: 92,
                                height: 92,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Image.asset('assets/images/driver.png',
                                        width: 92,
                                        height: 92,
                                        fit: BoxFit.cover),
                              )
                            : Image.asset('assets/images/driver.png',
                                width: 92, height: 92, fit: BoxFit.cover),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RequestRideHandler(
                    cnt: rideController,
                    cardDetails: driver,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // UI HELPERS
  // ─────────────────────────────────────────────────────────
  Widget _buildSwippedButton() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20),
      child: SlideAction(
        sliderButtonYOffset: 0,
        onSubmit: () => Get.toNamed(AppRoutes.searchLocationScreen,
            arguments: {'back_disable': true}),
        text: 'Lets Go...',
        textStyle: TextStyle(
          fontSize: 20,
          color: AppColors.whiteColor,
          fontWeight: FontWeight.w500,
          fontFamily: FontFamily.poppins,
        ),
        innerColor: AppColors.greenColor,
        outerColor: AppColors.blackButton,
        sliderButtonIcon: const Icon(
          Icons.arrow_right_alt,
          color: Color(0XFFF6F6F6),
          size: 24,
          weight: 900,
        ),
        sliderRotate: false,
        height: 56,
        sliderButtonIconPadding: 8,
      ),
    );
  }

  Widget _bgGlassDesign(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.whiteColor.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.whiteColor),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkColor.withValues(alpha: 0.01),
                offset: const Offset(0, -4),
                blurRadius: 4,
                spreadRadius: 0,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Map / Loading / Error ──────────────────────────────
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Loading map...'),
                ],
              ),
            )
          else if (_hasLocation)
            GoogleMap(
              mapToolbarEnabled: false,
              scrollGesturesEnabled: true,
              rotateGesturesEnabled: true,
              trafficEnabled: false,
              zoomGesturesEnabled: true,
              mapType: MapType.normal,
              initialCameraPosition: CameraPosition(
                target: _currentPosition ?? _defaultLocation,
                zoom: currentZoom,
              ),
              markers: _buildMarkers(),
              polylines: _polylines,
              onMapCreated: (controller) {
                _mapController = controller;
              },
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              circles: {
                Circle(
                  circleId: const CircleId('currentDriver'),
                  center: _currentPosition ?? _defaultLocation,
                  radius: 30,
                  strokeColor: Colors.white,
                  strokeWidth: 2,
                  fillColor: const Color(0xFF006491).withValues(alpha: 0.2),
                ),
              },
            )
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_off, size: 50),
                  const SizedBox(height: 20),
                  Text(_errorMessage.isNotEmpty
                      ? _errorMessage
                      : 'Unable to get your location'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => _initializeMap(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),

          // ── DraggableBottomSheet for passenger ─────────────────
          // ✅ Wrapped in Obx — no longer causes layout-during-layout crash
          Obx(() {
            final role = userController.userModel.value?.userProfile?.role;
            final rideStatus = mapOPTController.rideStatusData.value;
            final acceptRideModel = rideController.acceptRideModel.value;

            final shouldShow = role == AppConstants.passenger &&
                (acceptRideModel?.isRideAccepted == true ||
                    rideStatus?.acceptRide == true ||
                    rideStatus?.ongoingRide == true ||
                    rideStatus?.startRide == true ||
                    rideStatus?.arrivingRide == true ||
                    rideStatus?.driverCancel == true ||
                    rideStatus?.passengerCancel == true);

            if (!shouldShow) return const SizedBox.shrink();

            return DraggableBottomSheet(
              rideStatus: rideStatus,
              controller: mapOPTController,
            );
          }),

          // ── Ride request bottom sheet ──────────────────────────
          Obx(() {
            if (googleSearchLocationController.isModalOn.value &&
                rideController.viewInMap.value &&
                rideController.viewInMapReturn.value == false &&
                userController.userModel.value?.userProfile?.role ==
                    AppConstants.passenger) {
              return Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                right: 0,
                child: BottomSheet(
                  onClosing: () {},
                  backgroundColor: Colors.transparent,
                  enableDrag: false,
                  builder: (context) {
                    return RideRequestBottomSheet(
                      pickupLocation:
                          googleSearchLocationController.pickupController.text,
                      dropLocation:
                          googleSearchLocationController.dropController.text,
                      distance: googleSearchLocationController.distance.value
                          .toString(),
                      rideFare:
                          googleSearchLocationController.fare.value.toString(),
                    );
                  },
                ),
              );
            }
            return const SizedBox.shrink();
          }),

          // ── Custom Header ──────────────────────────────────────
          if (userController.userModel.value?.userProfile?.role ==
              AppConstants.passenger)
            Obx(() {
              final rideStatus = mapOPTController.rideStatusData.value;
              if (rideController.viewInMap.value &&
                      rideController.viewInMapReturn.value == false ||
                  rideStatus?.acceptRide == true ||
                  rideStatus?.ongoingRide == true ||
                  rideStatus?.startRide == true ||
                  rideStatus?.arrivingRide == true ||
                  rideStatus?.driverCancel == true ||
                  rideStatus?.passengerCancel == true ||
                  rideStatus?.completeRide == true) {
                return CustomHeader(mapOPTController: mapOPTController);
              }
              return MapCustomHeaderBack(rideController: rideController);
            }),

          // ── Safe Area Content ──────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Obx(() {
                  if (mapOPTController
                          .acceptedRideDriverData.value?.isRideAcceptedDriver ==
                      true) {
                    return SizedBox(height: 20.h);
                  }
                  return const SizedBox.shrink();
                }),
                const SizedBox(height: 20),

                // Driver online/offline toggle
                Obx(() {
                  final role =
                      userController.userModel.value?.userProfile?.role;
                  final isDriver = role == AppConstants.driver;
                  final isAcceptedDriver = mapOPTController
                          .acceptedRideDriverData.value?.isRideAcceptedDriver ??
                      false;
                  final status = mapOPTController.rideStatusData.value;

                  if (isDriver &&
                      !mapOPTController.acceptedRideDriverDataStatus.value &&
                      !isAcceptedDriver &&
                      rideController.isRideAccepted.value == false &&
                      (status?.acceptRide ?? false) == false &&
                      (status?.ongoingRide ?? false) == false &&
                      (status?.startRide ?? false) == false &&
                      (status?.arrivingRide ?? false) == false &&
                      (status?.driverCancel ?? false) == false &&
                      (status?.passengerCancel ?? false) == false &&
                      (status?.completeRide ?? false) == false) {
                    return AnimatedToggleSwitch();
                  }
                  return const SizedBox.shrink();
                }),

                // Driver current address bar
                Obx(() {
                  final role =
                      userController.userModel.value?.userProfile?.role;
                  final status = mapOPTController.rideStatusData.value;
                  final isAcceptedDriver = mapOPTController
                          .acceptedRideDriverData.value?.isRideAcceptedDriver ??
                      false;

                  final shouldShow = role == AppConstants.driver &&
                      (isAcceptedDriver ||
                          mapOPTController.acceptedRideDriverDataStatus.value ==
                              true ||
                          status?.acceptRide == true ||
                          status?.ongoingRide == true ||
                          status?.arrivingRide == true ||
                          status?.driverCancel == true ||
                          status?.passengerCancel == true ||
                          status?.startRide == true ||
                          status?.completeRide == true);

                  if (!shouldShow) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: SizedBox(
                      width: double.infinity,
                      child: GlassBackgroundWidget(
                        borderLeftRightRadius: 24,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            const Icon(Icons.location_pin, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FutureBuilder<Map<String, String>>(
                                    future: DirectionsService()
                                        .getCurrentAddressParts(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Text('Loading...');
                                      }
                                      if (snapshot.hasError ||
                                          !snapshot.hasData) {
                                        return const Text(
                                            'Error getting address');
                                      }
                                      return Text(
                                        snapshot.data!['firstLine'] ??
                                            'No address found',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          fontFamily: FontFamily.poppins,
                                          color: const Color(0xff171717),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      );
                                    },
                                  ),
                                  FutureBuilder<Map<String, String>>(
                                    future: DirectionsService()
                                        .getCurrentAddressParts(),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return const Text('Loading...');
                                      }
                                      if (snapshot.hasError ||
                                          !snapshot.hasData) {
                                        return const Text(
                                            'Error getting address');
                                      }
                                      return Text(
                                        snapshot.data!['secondLine'] ??
                                            'No address found',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: FontFamily.poppins,
                                          color: const Color(0xffA3A3A3),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                // Driver offline message
                Obx(() {
                  final offlineOnline = userController
                              .userModel.value?.userProfile?.role ==
                          AppConstants.driver &&
                      mapOPTController.userController.userModel.value
                              ?.driverProfile?.isOnline ==
                          false &&
                      mapOPTController.rideStatusData.value?.acceptRide !=
                          true &&
                      mapOPTController.rideStatusData.value?.ongoingRide !=
                          true &&
                      mapOPTController.rideStatusData.value?.arrivingRide !=
                          true &&
                      mapOPTController.rideStatusData.value?.driverCancel !=
                          true &&
                      mapOPTController.rideStatusData.value?.passengerCancel !=
                          true &&
                      mapOPTController.rideStatusData.value?.startRide !=
                          true &&
                      mapOPTController.rideStatusData.value?.completeRide !=
                          true;

                  if (offlineOnline) return const NoInternetMessageMap();
                  return const SizedBox.shrink();
                }),

                const Spacer(),

                // Passenger swipe button
                Obx(() {
                  final role =
                      userController.userModel.value?.userProfile?.role;
                  final status = mapOPTController.rideStatusData.value;

                  final swippedButton = role == AppConstants.passenger &&
                      googleSearchLocationController.isModalOn.value == false &&
                      rideController.isSwippedButtonShow.value == false &&
                      rideController.viewInMap.value == true &&
                      rideController.isRideAccepted.value == false &&
                      status?.acceptRide != true &&
                      status?.ongoingRide != true &&
                      status?.arrivingRide != true &&
                      status?.startRide != true &&
                      status?.driverCancel != true &&
                      status?.passengerCancel != true &&
                      status?.completeRide != true;

                  if (swippedButton) {
                    return Column(
                      children: [
                        _buildSwippedButton(),
                        const SizedBox(height: 100),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }),

                // Driver bottom panel
                Obx(() {
                  final role =
                      userController.userModel.value?.userProfile?.role;
                  final status = mapOPTController.rideStatusData.value;
                  final isAcceptedDriver = mapOPTController
                          .acceptedRideDriverData.value?.isRideAcceptedDriver ??
                      false;

                  // ── Waiting GIF ───────────────────────────────
                  final showPassengerGif = role == AppConstants.driver &&
                      mapOPTController.isPassengerRequest.value == false &&
                      userController.userModel.value?.driverProfile?.isOnline ==
                          true &&
                      mapOPTController.acceptedRideDriverDataStatus.value ==
                          false &&
                      rideController.isRideAccepted.value == false &&
                      status?.acceptRide != true &&
                      status?.ongoingRide != true &&
                      status?.arrivingRide != true &&
                      status?.startRide != true &&
                      status?.driverCancel != true &&
                      status?.passengerCancel != true &&
                      status?.completeRide != true;

                  if (showPassengerGif) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 90),
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      child: _bgGlassDesign(CustomPassengerWaitingGif()),
                    );
                  }

                  // ── Incoming ride request sheet ────────────────
                  if (role == AppConstants.driver &&
                      mapOPTController.isPassengerRequest.value == true &&
                      mapOPTController.acceptedRideDriverDataStatus.value ==
                          false &&
                      rideController.isRideAccepted.value == false &&
                      status?.acceptRide != true &&
                      status?.ongoingRide != true &&
                      status?.startRide != true &&
                      status?.arrivingRide != true &&
                      status?.driverCancel != true &&
                      status?.passengerCancel != true &&
                      status?.completeRide != true) {
                    return const PassengerRideRequestSheet();
                  }

                  // ── Active ride panel ──────────────────────────
                  final showActiveRide = role == AppConstants.driver &&
                      (isAcceptedDriver ||
                          mapOPTController.acceptedRideDriverDataStatus.value ==
                              true ||
                          status?.acceptRide == true ||
                          status?.ongoingRide == true ||
                          status?.arrivingRide == true ||
                          status?.driverCancel == true ||
                          status?.passengerCancel == true ||
                          status?.startRide == true
                      );

                  if (showActiveRide) {
                    return GlassBackgroundWidget(
                      child: Obx(() {
                        final rideStatus =
                            mapOPTController.rideStatusData.value;

                        final bool isOnTheWay =
                            rideStatus == null || rideStatus.acceptRide == true;

                        final bool isStartRide = rideStatus?.startRide == true;

                        final bool isArriving =
                            rideStatus?.arrivingRide == true;

                        final bool isOngoing = rideStatus?.ongoingRide == true;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),

                            // Distance / time + Cancel row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Obx(() {
                                  final rideData = mapOPTController
                                      .getRideDriverLocation.value;

                                  final distance = rideData
                                          ?.driverToPickup?.distance?.value ??
                                      0;
                                  final int time =
                                      rideData?.driverToPickup?.time?.value ??
                                          0;
                                  String convertSecondsToTime(int seconds) {
                                    if (seconds < 0) return '0 Min';

                                    final int days = seconds ~/ 86400;
                                    final int hours = (seconds % 86400) ~/ 3600;
                                    final int minutes = (seconds % 3600) ~/ 60;
                                    final int secs = seconds % 60;

                                    if (days > 0) {
                                      if (hours > 0)
                                        return '$days Day${days > 1 ? 's' : ''} $hours Hr${hours > 1 ? 's' : ''}';
                                      return '$days Day${days > 1 ? 's' : ''}';
                                    }

                                    if (hours > 0) {
                                      if (minutes > 0)
                                        return '$hours Hr${hours > 1 ? 's' : ''} $minutes Min';
                                      return '$hours Hr${hours > 1 ? 's' : ''}';
                                    }

                                    if (minutes > 0) {
                                      if (secs > 0)
                                        return '$minutes Min $secs Sec';
                                      return '$minutes Min';
                                    }

                                    return '$secs Sec';
                                  }

                                  String convertMetersToDistance(
                                      double meters) {
                                    if (meters < 0) return '0 M';

                                    if (meters < 1000) {
                                      return '${meters.toStringAsFixed(0)} M';
                                    }

                                    final double km = meters / 1000;

                                    if (km < 100) {
                                      return '${km.toStringAsFixed(2)} KM';
                                    }

                                    return '${km.toStringAsFixed(1)} KM';
                                  }

                                  return Text(
                                    '( ${convertSecondsToTime(time)}) ${convertMetersToDistance(distance.toDouble())}',
                                    style: TextStyle(
                                      color: AppColors.timeAndDurationColor,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: FontFamily.poppins,
                                      fontSize: 20.sp,
                                    ),
                                  );
                                }),
                                const SizedBox(width: 10),
                                Visibility(
                                  visible: rideStatus?.acceptRide == true ||
                                      rideStatus?.ongoingRide == true ||
                                      rideStatus?.arrivingRide == true,
                                  child: GestureDetector(
                                    onTap: () {
                                      mapOPTController
                                          .showCancelReasonDialog.value = true;
                                      _showCancelReasonDialog(context);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(50),
                                        border: Border.all(
                                            color: Colors.red, width: 1),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.block,
                                              color: Colors.red, size: 18),
                                          SizedBox(width: 6),
                                          Text(
                                            'Cancel',
                                            style: TextStyle(
                                                color: Colors.red,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              ],
                            ),

                            const SizedBox(height: 28),
                            Divider(
                                height: 1,
                                color: Colors.black.withOpacity(0.2)),
                            const SizedBox(height: 16),

                            // ── Passenger Card Info ──────────────────────────
                            Obx(() {
                              final rideStatus =
                                  mapOPTController.rideStatusData.value;

                              // ✅ Show loader while data hasn't arrived
                              if (rideStatus == null) {
                                return const SizedBox(
                                  height: 70,
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                );
                              }

                              // ✅ Safely resolve image — never pass empty string to Image.network
                              // final filename = rideStatus.passenger?.image?.filename;
                              final filename =
                                  rideStatus.ride?.passenger?.image?.filename;
                              final hasImage =
                                  filename != null && filename.isNotEmpty;
                              final imageUrl = hasImage
                                  ? '${ApiUrls.imageBaseUrl}$filename'
                                  : null;

                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(50),
                                        child: imageUrl != null
                                            ? Image.network(
                                                imageUrl,
                                                height: 50,
                                                width: 50,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Image.asset(
                                                    'assets/images/default_image.jpg',
                                                    height: 50,
                                                    width: 50,
                                                    fit: BoxFit.cover,
                                                  );
                                                },
                                              )
                                            : Image.asset(
                                                'assets/images/default_image.jpg',
                                                height: 50,
                                                width: 50,
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                      const SizedBox(width: 10),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            // ✅ No more 'null' — safe fallback
                                            rideStatus.ride?.passenger?.name ??
                                                'Unknown Passenger',
                                            style: TextStyle(
                                              color: const Color(0xff171717),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              fontFamily: FontFamily.poppins,
                                            ),
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                '\$${rideStatus.ride?.fare ?? 0.0} ',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                // ✅ Correct meters → KM conversion
                                                '(${((rideStatus.ride?.destinationMeters ?? 0) / 1000).toStringAsFixed(2)} KM)',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      launchUrl(
                                        Uri.parse(
                                            "tel:${rideStatus.passenger?.phone}"),
                                      );
                                    },
                                    child: RepaintBoundary(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.whiteColor,
                                          borderRadius:
                                              BorderRadius.circular(50),
                                          border: Border.all(
                                              color: AppColors.greyColor200),
                                        ),
                                        child: SvgPicture.asset(
                                            Assets.icons.driverCardPhone),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                            const SizedBox(height: 24),

                            // ── PRIMARY ACTION BUTTON ─────────────
                            Obx(() {
                              final locationData =
                                  mapOPTController.getRideDriverLocation.value;
                              final rideStatus =
                                  mapOPTController.rideStatusData.value;

                              // Enables "Arrive in Place" only when driver < 150m from PICKUP
                              final bool enableArriveInPlace =
                                  (rideStatus?.ongoingRide == true) &&
                                      (locationData?.driverToPickup?.distance
                                                  ?.value ??
                                              200) <
                                          150;

                              // Enables "Complete" only when driver < 150m from DESTINATION
                              final bool enableComplete =
                                  (rideStatus?.startRide == true) &&
                                      (locationData?.driverToDestination
                                                  ?.distance?.value ??
                                              200) <
                                          150;

                              debugPrint(
                                  '================>>>>>>>>>>> Location Data ${locationData?.driverToDestination?.distance} ${locationData?.driverToPickup?.distance} ');

                              String getButtonTitle() {
                                if (rideStatus == null) return 'Loading...';
                                if (rideStatus.acceptRide == true)
                                  return 'On the way';
                                if (rideStatus.ongoingRide == true)
                                  return 'Arrive in Place';
                                if (rideStatus.arrivingRide == true)
                                  return 'Start Ride';
                                if (rideStatus.startRide == true)
                                  return 'Complete';
                                return 'Loading...';
                              }

                              bool isButtonEnabled() {
                                if (rideStatus == null) return false;
                                if (rideStatus.acceptRide == true) return true;
                                if (rideStatus.ongoingRide == true)
                                  return enableArriveInPlace;
                                if (rideStatus.arrivingRide == true)
                                  return true;
                                if (rideStatus.startRide == true)
                                  return enableComplete;
                                return false;
                              }

                              return mapOPTController.isRideStatusChangeLoading
                                              .value ==
                                          true ||
                                      mapOPTController
                                              .isCompleteRideLoading.value ==
                                          true
                                  ? CustomLoader()
                                  : CustomPrimaryButton(
                                      title: getButtonTitle(),
                                      onHandler: isButtonEnabled()
                                          ? () async {
                                              final rideId =
                                                  rideStatus?.ride?.id;
                                              if (rideId == null) return;

                                              if (rideStatus?.acceptRide ==
                                                  true) {
                                                // "On the way" → change to ongoing
                                                debugPrint(
                                                    '🚕 accepted → ongoing');
                                                mapOPTController
                                                    .rideStatusChange(
                                                        rideId, 'ongoing');
                                              } else if (rideStatus
                                                      ?.ongoingRide ==
                                                  true) {
                                                // "Arrive in Place" → change to arriving
                                                debugPrint(
                                                    '🚕 ongoing → arriving');
                                                mapOPTController
                                                    .rideStatusChange(
                                                        rideId, 'arriving');
                                              } else if (rideStatus
                                                      ?.arrivingRide ==
                                                  true) {
                                                // "Start Ride" → change to start_ride
                                                debugPrint(
                                                    '🚕 arriving → start_ride');
                                                mapOPTController
                                                    .rideStatusChange(
                                                        rideId, 'start_ride');
                                              } else if (rideStatus
                                                      ?.startRide ==
                                                  true) {
                                                // "Complete" → complete the ride
                                                debugPrint(
                                                    '🚕 start_ride → complete');
                                                mapOPTController
                                                    .isPassengerRequest
                                                    .value = false;
                                                mapOPTController
                                                    .completeRideHandler(
                                                        rideId, 0);
                                              }
                                            }
                                          : null,
                                    );
                            }),
                            /*Obx(() {
                              final locationData = mapOPTController.getRideDriverLocation.value;
                              final ride = mapOPTController.rideStatusData;
                              final rideStatus = ride.value;

                              final bool disible = (rideStatus?.ongoingRide == true) &&
                                  (locationData?.driverToPickup?.distance?.value ?? 200) < 150;

                              final bool disibleCompleted = rideStatus?.startRide == true &&
                                  (locationData?.driverToDestination?.distance?.value ?? 200) < 150;

                              // ✅ Debug prints
                              debugPrint('🔴 disible: $disible | ongoingRide: ${rideStatus?.ongoingRide} | pickupDistance: ${locationData?.driverToPickup?.distance?.value ?? 'null'}');
                              debugPrint('🟢 disibleCompleted: $disibleCompleted | startRide: ${rideStatus?.startRide} | destinationDistance: ${locationData?.driverToDestination?.distance?.value ?? 'null'}');

                              String getButtonTitle() {
                                if (rideStatus == null) return 'Loading...';

                                switch (true) {
                                  case _ when rideStatus.acceptRide == true:
                                    return 'On the way';
                                  case _ when rideStatus.ongoingRide == true:
                                    return 'Arrive in Place';
                                  case _ when rideStatus.startRide == true:
                                    return 'Complete';
                                  case _ when rideStatus.arrivingRide == true:
                                    return 'Start Ride';
                                  default:
                                    return 'Loading...';
                                }
                              }

                              return CustomPrimaryButton(
                                title: getButtonTitle(),
                                onHandler: (disible || disibleCompleted) ? () async {
                                  final rideId = rideStatus?.ride?.id;
                                  if (rideId == null) return;

                                  if (rideStatus?.acceptRide == true) {
                                    debugPrint('🚕 Moving to ongoing');
                                    mapOPTController.rideStatusChange(rideId, 'ongoing');
                                  } else if (rideStatus?.ongoingRide == true) {
                                    debugPrint('🚕 Moving to arriving');
                                    mapOPTController.rideStatusChange(rideId, 'arriving');
                                    // ❌ DON'T try to set disible.value = false - it's not RxBool
                                    // The button will automatically update when locationData changes
                                  } else if (rideStatus?.startRide == true) {
                                    debugPrint('🚕 Moving Start Ride');
                                    mapOPTController.rideStatusChange(rideId, 'start_ride');
                                  } else if (rideStatus?.arrivingRide == true) {
                                    debugPrint('🚕 Completing ride');
                                    mapOPTController.isPassengerRequest.value = false;
                                    mapOPTController.completeRideHandler(rideId, 0);
                                  }
                                } : null,
                              );
                            }),*/
                            const SizedBox(height: 80),
                          ],
                        );
                      }),
                    );
                  }

                  return const SizedBox.shrink();
                }),
              ],
            ),
          ),

          // ── Location disabled banner ───────────────────────────
          StreamBuilder<bool>(
            stream: _locationStatusStream(),
            builder: (context, snapshot) {
              if (snapshot.data == false) {
                return LocationDisableBannerWidget();
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Stream<bool> _locationStatusStream() {
    return Stream.periodic(const Duration(seconds: 5), (_) async {
      return await Geolocator.isLocationServiceEnabled();
    }).asyncMap((event) => event);
  }

  // ─────────────────────────────────────────────────────────
  // CANCEL REASON DIALOG
  // ─────────────────────────────────────────────────────────
  void _showCancelReasonDialog(BuildContext context) {
    final reasons = [
      'Passenger no show',
      'Difficult pickup location',
      'Unaccompanied minor',
      'No car seat',
      'Too many bags',
      'Other safety concern',
      'Destination changed',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white.withOpacity(0.3),
      barrierColor: Colors.transparent,
      builder: (context) {
        String? selectedReason;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return GlassBackgroundWidget(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 30,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close,
                              size: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Choose Reason For Cancelling',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  ...reasons.map((reason) => GestureDetector(
                        onTap: () {
                          setDialogState(() => selectedReason = reason);
                          mapOPTController.selectedReason?.text = reason;
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: selectedReason == reason
                                        ? Colors.green
                                        : Colors.grey,
                                    width: 2,
                                  ),
                                  color: selectedReason == reason
                                      ? Colors.green
                                      : Colors.transparent,
                                ),
                                child: selectedReason == reason
                                    ? const Icon(Icons.check,
                                        size: 13, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Text(reason,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      )),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        disabledBackgroundColor: Colors.red.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50)),
                      ),
                      onPressed: selectedReason == null
                          ? null
                          : () async {
                              final rideId = mapOPTController
                                  .rideStatusData.value?.ride?.id;
                              if (rideId == null) {
                                debugPrint('❌ Ride ID is null');
                                return;
                              }
                             final cnt =  mapOPTController
                                  .cancelRideByDriverHandler(rideId);
                              if( cnt == true ){
                                _polylines.clear();
                                _buildMarkers().clear();
                                Navigator.pop(context);
                              }
                            },
                      child: Obx(() {
                        if (mapOPTController.isRideCanceledLoader.value) {
                          return const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          );
                        }
                        return const Text(
                          'Cancel Ride',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────
  // DISPOSE
  // ─────────────────────────────────────────────────────────
  @override
  void dispose() {
    _mapController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    positionStream?.cancel();
    SocketServices.socket?.off('new-ride-request');
    SocketServices.socket?.off('cancel-ride-request');
    SocketServices.socket?.off('ride-accepted');
    SocketServices.socket?.off('ride-accepted-driver');
    SocketServices.socket?.off('get-ride-driver-location');
    SocketServices.socket?.off('ride-status');
    _stopLocationTracking();
    super.dispose();
  }
}
