part of '../../map_screen.dart';

extension _Tracking on _MapScreenState {
  void startLocationTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    // Subscribe to the magnetometer-driven compass for real-time heading.
    // GPS heading only updates when moving and at ~1 Hz; the device compass
    // updates instantly as the phone rotates — this is what Google Maps uses
    // for the blue arrow / cone direction indicator.
    _compassStream = FlutterCompass.events?.listen((CompassEvent event) {
      final double? h = event.heading;
      if (h == null || h.isNaN) return;
      // CompassEvent.heading is 0-360 (with -1 when unavailable on some
      // platforms); normalize and feed into the marker rotation Rx.
      final double normalized = (h % 360 + 360) % 360;
      mapOPTController.headingDegrees.value = normalized;
    });

    String? token = await PrefsHelper.getString(AppConstants.bearerToken);

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
    ).listen((Position position) async {
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

      if (distance >= 20) {
        _lastSentPosition = position;
        sendLocation(position, token);
      }
    });
  }

  void _updateLocalMarker(Position position) {
    mapOPTController.currentLatitudePosition?.value = position.latitude;
    mapOPTController.currentLongitudePosition?.value = position.longitude;
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

    // Only the driver updates the polyline from their own GPS position.
    // The passenger's polyline is updated via the get-ride-driver-location socket.
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
          CameraPosition(target: newLocation, zoom: currentZoom),
        ),
      );
    }
  }

  void stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _compassStream?.cancel();
    _compassStream = null;
    _isTracking = false;
  }
}
