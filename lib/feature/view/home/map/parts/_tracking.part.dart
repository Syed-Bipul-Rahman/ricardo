part of '../../map_screen.dart';

extension _Tracking on _MapScreenState {
  void startLocationTracking() {
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

    String token = '';
    unawaited(
      PrefsHelper.getString(AppConstants.bearerToken).then((value) {
        token = value;
      }),
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: mapOPTController.isInActiveRide ? 1 : 3,
      ),
    ).listen((Position position) async {
      if (_liveLocationDiag) {
        final isDriver = userController.userModel.value?.userProfile?.role ==
            AppConstants.driver;
        if (isDriver && mapOPTController.isInActiveRide) {
          debugPrint(
            'GPS_RECEIVED ${DateTime.now().toIso8601String()} '
            'lat=${position.latitude.toStringAsFixed(6)} '
            'lng=${position.longitude.toStringAsFixed(6)} '
            'speed=${position.speed.toStringAsFixed(2)} '
            'acc=${position.accuracy.toStringAsFixed(1)} '
            'hdg=${position.heading.toStringAsFixed(1)} '
            'gpsTs=${position.timestamp}',
          );
        }
      }

      _updateLocalMarker(position);
      unawaited(mapOPTController.maybeRefreshAddress());

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
      final inRide = mapOPTController.isInActiveRide;
      // During an active ride, push more often so passenger polls see fresh
      // coordinates (Uber/Pathao-like). Outside rides, keep quieter cadence.
      final heartbeatDue = inRide
          ? (_lastLocationSentAt == null ||
              now.difference(_lastLocationSentAt!) >=
                  const Duration(milliseconds: 400))
          : (_lastLocationSentAt == null ||
              now.difference(_lastLocationSentAt!) >=
                  const Duration(seconds: 10));
      final movedEnough = inRide ? distance >= 1.0 : distance >= 3;
      if (movedEnough || heartbeatDue) {
        if (sendLocation(position, token)) {
          _lastSentPosition = position;
          _lastLocationSentAt = now;
        }
      }
    });
  }

  void _updateLocalMarker(Position position) {
    final target = LatLng(position.latitude, position.longitude);
    final applied = mapOPTController.applyCurrentGps(
      latitude: position.latitude,
      longitude: position.longitude,
      gpsTimestamp: position.timestamp,
    );
    if (!applied) return;

    final isDriver = userController.userModel.value?.userProfile?.role ==
        AppConstants.driver;
    if (!_hasValidVisualDeviceMarker()) {
      _placeInitialDeviceMarkerIfNeeded(
        target,
        heading: position.heading,
      );
    } else if (isDriver) {
      _animateCurrentMarkerTo(
        target,
        reportedSpeedMps: position.speed,
        reportedHeading: position.heading,
      );
    } else {
      mapOPTController.animatedCurrentMarkerPosition.value = target;
      mapOPTController.liveOverlayRevision.value++;
    }

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
      // Keep GeoJSON Point intact for strict backends. Optional telemetry is
      // sent as sibling fields — ignored by older servers, useful when newer
      // ones forward them into get-ride-driver-location.
      SocketServices.socket?.emit('update-user-location', {
        "accessToken": token,
        "location": {
          "type": "Point",
          "coordinates": [newLocation.longitude, newLocation.latitude],
        },
        "speed": position.speed.isFinite ? position.speed : 0,
        "heading": position.heading.isFinite ? position.heading : null,
        "accuracy": position.accuracy.isFinite ? position.accuracy : null,
        "updatedAt": DateTime.now().toUtc().toIso8601String(),
      });

      if (_liveLocationDiag && mapOPTController.isInActiveRide) {
        debugPrint(
          'SOCKET_EMIT ${DateTime.now().toIso8601String()} '
          'update-user-location '
          'lat=${newLocation.latitude.toStringAsFixed(6)} '
          'lng=${newLocation.longitude.toStringAsFixed(6)} '
          'speed=${position.speed.toStringAsFixed(2)}',
        );
      }
    }

    // Never chase the camera on every GPS sample during an active ride.
    // Continuous animateCamera floods the Maps SDK with tile requests
    // (REQUEST_TIMEOUT / ImageReader buffer exhaustion) and the marker
    // appears frozen while tiles/GC dominate. Framing is handled by
    // _ensureCarTravelVisible on live samples only.
    if (!mapOPTController.isInActiveRide) {
      _queueCameraToCurrentLocation();
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
