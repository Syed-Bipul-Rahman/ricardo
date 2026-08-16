part of '../../map_screen.dart';

extension _Bootstrap on _MapScreenState {
  Future<void> loadStatus() async {
    final bool? data = await userController.fetchActiveRideStatus();
    if (data == true) {
      final rideStatus = mapOPTController.rideStatusData.value;
      if (rideStatus != null &&
          (rideStatus.acceptRide == true ||
              rideStatus.ongoingRide == true ||
              rideStatus.arrivingRide == true ||
              rideStatus.startRide == true)) {
        final rideId = rideStatus.ride?.id;
        if (rideId != null && rideId.isNotEmpty) {
          mapOPTController.startRideLocationSync(rideId);
        }
        if (rideStatus.ongoingRide == true) {
          await loadAcceptedRideRoute();
        } else if (rideStatus.startRide == true) {
          await pickupToDestinationRoute();
        } else if (rideStatus.arrivingRide == true) {
          _routeGeneration++;
          _polylines = <Polyline>{};
          _fullRoutePoints = <LatLng>[];
          _routeTarget = null;
        }
      }
    }
  }

  void clearRideState() {
    mapOPTController.clearRideSession();
  }

  void clearRideMapUi() {
    _routeGeneration++;
    // Replace the collections so Google Maps detects removals immediately.
    _polylines = <Polyline>{};
    markers = <Marker>{};
    _fullRoutePoints = <LatLng>[];
    _routeTarget = null;
    _remoteDriverTarget = null;
    _lastAnimatedRouteUpdateAt = null;
    _isReFetchingRoute = false;
    if (mounted) setState(() {});
  }

  Future<void> finishRide({String? rideId}) async {
    final role = userController.userModel.value?.userProfile?.role;
    debugPrint('🧹 finishRide() called | role=$role rideId=$rideId');

    // ── 1. IMMEDIATE STATE RESET (ensures Nav Bar & Slider show up instantly) ──
    rideController.isRideAccepted.value = false;
    rideController.acceptRideModel.value = null;
    rideController.viewInMap.value = true;
    rideController.viewInMapReturn.value = false;
    rideController.rideCancel.value = false;
    rideController.isSwippedButtonShow.value = false;
    rideController.drivers.clear();

    mapOPTController.acceptedRideDriverDataStatus.value = false;
    mapOPTController.acceptedRideDriverData.value = null;
    mapOPTController.isPassengerRequest.value = false;
    mapOPTController.rideStatusData.value = null;
    mapOPTController.rideRequestReceivedAt.value = null;
    mapOPTController.isCurrentMarkerShowOrNot.value = true;
    mapOPTController.getRideDriverLocation.value = null;

    googleSearchLocationController.isModalOn.value = false;
    googleSearchLocationController.cleanField();

    // Force UI rebuild immediately
    if (mounted) setState(() {});

    // ── 2. BACKGROUND CLEANUP ─────────────────────────────────────────────
    final resolvedRideId = rideId ?? mapOPTController.activeRideId;
    if (resolvedRideId != null && resolvedRideId.isNotEmpty) {
      mapOPTController.markRideFinished(resolvedRideId);
    }

    clearRideState(); // Redundant clearing of rideStatusData
    clearRideMapUi();
    moveToCurrentLocation();

    // Sync status with server
    await userController.fetchActiveRideStatus();

    debugPrint('🧹 finishRide() background sync done');
    DriverLocationService().stop();

    // ── 3. FINAL REFRESH ──────────────────────────────────────────────────
    userController.userModel.refresh();
    if (mounted) setState(() {});

    // ── 4. PERSISTENCE CLEANUP ────────────────────────────────────────────
    PrefsHelper.setString('status', '');
    PrefsHelper.setString('ride-accepted-data', '');
    PrefsHelper.setString('driver-status', '');
    PrefsHelper.setString('ride-accepted-driver-data', '');
  }

  Future<void> initializeMap() async {
    if (!mounted) return;

    final bool hasCached = await _seedFromCachedLocation();

    if (!mounted) return;
    setState(() {
      _isLoading = !hasCached;
      _errorMessage = '';
    });

    bool hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (!hasCached) {
          _errorMessage = 'Location permission is required to use this app';
        }
      });
      return;
    }

    await getCurrentLocation();
    await connectSocket();
    await userController.fetchUser();
    await loadAcceptedRideRoute();

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<bool> _seedFromCachedLocation() async {
    final cachedLat = double.tryParse(await PrefsHelper.getString('last_lat'));
    final cachedLng = double.tryParse(await PrefsHelper.getString('last_lng'));
    if (cachedLat == null || cachedLng == null) return false;

    mapOPTController.currentLatitudePosition?.value = cachedLat;
    mapOPTController.currentLongitudePosition?.value = cachedLng;
    if (mounted) {
      setState(() {
        _hasLocation = true;
      });
    }
    return true;
  }

  Future<bool> requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        showLocationPermissionDeniedDialog(
          context,
          onRetry: initializeMap,
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      showLocationPermissionPermanentlyDeniedDialog(context);
      return false;
    }

    return true;
  }

  Future<void> getCurrentLocation() async {
    final Position? position = await resolveInitialPosition();

    if (!mounted) return;

    if (position == null) {
      if (_hasLocation) return;
      setState(() {
        _errorMessage = 'Could not get your location. Tap retry.';
        _hasLocation = false;
      });
      return;
    }

    mapOPTController.currentLatitudePosition?.value = position.latitude;
    mapOPTController.currentLongitudePosition?.value = position.longitude;
    PrefsHelper.setString('last_lat', position.latitude);
    PrefsHelper.setString('last_lng', position.longitude);
    unawaited(mapOPTController.getLocation());

    setState(() {
      _hasLocation = true;
      _errorMessage = '';
    });

    startLocationTracking();

    if (_mapController != null) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: currentZoom,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    }
  }
}
