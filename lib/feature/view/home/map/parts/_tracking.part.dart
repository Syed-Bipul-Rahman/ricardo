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
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
      ),
    ).listen((Position position) async {
      _updateLocalMarker(position);

      if (_lastSentPosition == null) {
        if (sendLocation(position, token)) {
          _lastSentPosition = position;
          _lastLocationSentAt = DateTime.now();
        }
        return;
      }

      double distance = Geolocator.distanceBetween(
        _lastSentPosition!.latitude,
        _lastSentPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      final now = DateTime.now();
      final heartbeatDue = mapOPTController.isInActiveRide &&
          (_lastLocationSentAt == null ||
              now.difference(_lastLocationSentAt!) >=
                  const Duration(seconds: 10));
      if (distance >= 3 || heartbeatDue) {
        if (sendLocation(position, token)) {
          _lastSentPosition = position;
          _lastLocationSentAt = now;
        }
      }
    });
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

  bool sendLocation(Position position, String? token) {
    LatLng newLocation = LatLng(position.latitude, position.longitude);

    mapOPTController.currentLatitudePosition?.value = position.latitude;
    mapOPTController.currentLongitudePosition?.value = position.longitude;
    PrefsHelper.setString('last_lat', position.latitude);
    PrefsHelper.setString('last_lng', position.longitude);

    final socketConnected = SocketServices.socket?.connected == true;
    if (socketConnected) {
      SocketServices.socket?.emit('update-user-location', {
        "accessToken": token,
        "location": {
          "type": "Point",
          "coordinates": [newLocation.longitude, newLocation.latitude]
        }
      });
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
    return socketConnected;
  }

  void stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _compassStream?.cancel();
    _compassStream = null;
    _lastSentPosition = null;
    _lastLocationSentAt = null;
    _isTracking = false;
  }
}
