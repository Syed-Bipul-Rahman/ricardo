part of '../../map_screen.dart';

extension _Tracking on _MapScreenState {
  void startLocationTracking() async {
    if (_isTracking) return;
    _isTracking = true;

    String? token = await PrefsHelper.getString(AppConstants.bearerToken);

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
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

  void sendLocation(Position position, String? token) {
    LatLng newLocation = LatLng(position.latitude, position.longitude);

    mapOPTController.currentLatitudePosition?.value = position.latitude;
    mapOPTController.currentLongitudePosition?.value = position.longitude;

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
    _isTracking = false;
  }
}
