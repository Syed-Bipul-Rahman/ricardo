// ignore_for_file: invalid_use_of_protected_member, use_build_context_synchronously
part of '../../map_screen.dart';

extension _Bootstrap on _MapScreenState {
  Future<void> loadStatus() async {
    final bool? data = await userController.fetchActiveRideStatus();
    if (data == true) {
      final rideStatus = mapOPTController.rideStatusData.value;
      if (rideStatus != null &&
          (rideStatus.acceptRide == true ||
              rideStatus.ongoingRide == true ||
              rideStatus.arrivingRide == true)) {}
    }
  }

  void clearRideState() {
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

  Future<void> initializeMap() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    bool hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Location permission is required to use this app';
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
      setState(() {
        _errorMessage = 'Could not get your location. Tap retry.';
        _hasLocation = false;
      });
      return;
    }

    mapOPTController.currentLatitudePosition?.value = position.latitude;
    mapOPTController.currentLongitudePosition?.value = position.longitude;

    // Resolve human-readable address, but don't gate the map on it.
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
          ),
        ),
      );
    }
  }
}
