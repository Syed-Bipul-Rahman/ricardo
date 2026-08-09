part of '../../map_screen.dart';

extension _Tracking on _MapScreenState {
  void startLocationTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
      final double? h = event.heading;
      if (h == null || h.isNaN) return;
      final double normalized = (h % 360 + 360) % 360;
      final now = DateTime.now();
      final previous = mapOPTController.headingDegrees.value;
      final headingDelta = ((normalized - previous + 540) % 360) - 180;
      if (_lastHeadingUpdateAt != null &&
          now.difference(_lastHeadingUpdateAt!) <
              const Duration(milliseconds: 100)) {
        return;
      }
      if (headingDelta.abs() < 1.5) return;
      _lastHeadingUpdateAt = now;
      mapOPTController.headingDegrees.value = normalized;
    });

    String? token = await PrefsHelper.getString(AppConstants.bearerToken);

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (!_shouldAcceptPosition(position)) return;
      _lastAcceptedPosition = position;
      _updateLocalMarker(position);

      if (_lastSentPosition == null) {
        _lastSentPosition = position;
        sendLocation(position, token);
        return;
      }

      double distance = Geolocator.distanceBetween(
        _lastSentPosition!.latitude,
        _lastSentPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance >= 5) {
        _lastSentPosition = position;
        sendLocation(position, token);
      }
    });
  }

  bool _shouldAcceptPosition(Position position) {
    // Very inaccurate fixes commonly jump while a stationary phone is indoors.
    if (position.accuracy > 75) return false;

    final previous = _lastAcceptedPosition;
    if (previous == null) return true;

    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );

    // Ignore tiny coordinate noise. Keep genuine low-speed movement once it
    // crosses the conservative eight-metre stationary dead zone.
    if (distance < 3) return false;
    if (position.speed >= 0 && position.speed < 0.5 && distance < 8) {
      return false;
    }
    if (position.accuracy > 35 && distance < 12) return false;
    return true;
  }

  void _updateLocalMarker(Position position) {
    final target = LatLng(position.latitude, position.longitude);
    final isDriver = userController.userModel.value?.userProfile?.role ==
        AppConstants.driver;
    if (isDriver) {
      _animateCurrentMarkerTo(
        target,
        reportedSpeedMps: position.speed,
      );
    } else {
      _currentMarkerAnimation?.cancel();
      mapOPTController.animatedCurrentMarkerPosition.value = target;
    }
    mapOPTController.currentLatitudePosition?.value = position.latitude;
    mapOPTController.currentLongitudePosition?.value = position.longitude;

    if (!mapOPTController.isInActiveRide) return;

    final rideId = mapOPTController.activeRideId;
    if (rideId != null && rideId.isNotEmpty) {
      mapOPTController.maybeEmitGetDriverLocation(rideId);
    }
  }

  void sendLocation(Position position, String? token) {
    LatLng newLocation = LatLng(position.latitude, position.longitude);

    mapOPTController.currentLatitudePosition?.value = position.latitude;
    mapOPTController.currentLongitudePosition?.value = position.longitude;
    PrefsHelper.setString('last_lat', position.latitude);
    PrefsHelper.setString('last_lng', position.longitude);

    SocketServices.socket?.emit('update-user-location', {
      "accessToken": token,
      "location": {
        "type": "Point",
        "coordinates": [newLocation.longitude, newLocation.latitude]
      }
    });

    final rideStatus = mapOPTController.rideStatusData.value;
    final bool isDriver = userController.userModel.value?.userProfile?.role ==
        AppConstants.driver;

    if (isDriver &&
        rideStatus != null &&
        (rideStatus.acceptRide == true ||
            rideStatus.ongoingRide == true ||
            rideStatus.arrivingRide == true ||
            rideStatus.startRide == true ||
            rideStatus.completeRide == true)) {
      updatePolylineForDriverPosition(newLocation);
    }

    if (_mapController != null && mounted) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: newLocation,
            zoom: currentZoom,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    }
  }

  void stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _compassStream?.cancel();
    _compassStream = null;
    _lastAcceptedPosition = null;
    _isTracking = false;
  }
}
