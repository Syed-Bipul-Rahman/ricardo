part of '../../map_screen.dart';

extension _Routes on _MapScreenState {
  Future<void> loadAcceptedRideRoute() async {
    try {
      final acceptedRide = mapOPTController.rideStatusData.value;
      if (acceptedRide == null) return;

      final bool isPassenger =
          userController.userModel.value?.userProfile?.role ==
              AppConstants.passenger;

      LatLng driverLocation;
      if (isPassenger) {
        final coords = mapOPTController
            .getRideDriverLocation.value?.driverLocation?.coordinates;
        if (coords == null || coords.length < 2) return;
        driverLocation = mapOPTController.animatedRemoteDriverPosition.value ??
            LatLng(coords[1], coords[0]);
      } else {
        final Position currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        driverLocation = mapOPTController.animatedCurrentMarkerPosition.value ??
            LatLng(
              currentPosition.latitude,
              currentPosition.longitude,
            );
      }

      final pickupCoords = acceptedRide.ride?.pickupLocation?.coordinates;
      if (pickupCoords == null || pickupCoords.length < 2) return;
      final LatLng pickupLocation = LatLng(pickupCoords[1], pickupCoords[0]);

      if (driverLocation.latitude == 0.0 || pickupLocation.latitude == 0.0) {
        debugPrint('Skipping — coords not ready');
        return;
      }

      final bool onGoingRide = acceptedRide.ongoingRide == true;
      if (!onGoingRide) return;

      final routeGeneration = ++_routeGeneration;
      final activeRoutePoints = await DirectionsService.getPolyline(
        driverLocation,
        pickupLocation,
      );
      if (routeGeneration != _routeGeneration) return;
      if (activeRoutePoints.isEmpty) return;

      _fullRoutePoints = List.from(activeRoutePoints);
      _lastAnimatedRouteUpdateAt = null;
      _routeTarget = pickupLocation;

      if (!mounted) return;
      setState(() {
        markers.removeWhere((m) =>
            m.markerId.value == 'driver_location' ||
            m.markerId.value == 'pickup_location');
        _polylines = {
          _buildRidePolyline('driver_to_pickup', activeRoutePoints),
        };
        final isPassenger = userController.userModel.value?.userProfile?.role ==
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
      });

      final bounds = boundsFromLatLng(activeRoutePoints);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 48),
      );
    } catch (e) {
      debugPrint('_loadAcceptedRideRoute error: $e');
    }
  }

  Future<void> pickupToDestinationRoute() async {
    try {
      final acceptedRide = mapOPTController.rideStatusData.value;
      if (acceptedRide == null) return;

      final bool isPassenger =
          userController.userModel.value?.userProfile?.role ==
              AppConstants.passenger;

      LatLng driverLocation;
      if (isPassenger) {
        final coords = mapOPTController
            .getRideDriverLocation.value?.driverLocation?.coordinates;
        if (coords == null || coords.length < 2) return;
        driverLocation = mapOPTController.animatedRemoteDriverPosition.value ??
            LatLng(coords[1], coords[0]);
      } else {
        final Position currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        driverLocation = mapOPTController.animatedCurrentMarkerPosition.value ??
            LatLng(
              currentPosition.latitude,
              currentPosition.longitude,
            );
      }

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
      if (!startRide) return;

      final routeGeneration = ++_routeGeneration;
      final activeRoutePoints = await DirectionsService.getPolyline(
        driverLocation,
        destinationLocation,
      );
      if (routeGeneration != _routeGeneration) return;
      if (activeRoutePoints.isEmpty) return;

      _fullRoutePoints = List.from(activeRoutePoints);
      _lastAnimatedRouteUpdateAt = null;
      _routeTarget = destinationLocation;

      if (!mounted) return;
      setState(() {
        markers.removeWhere((m) =>
            m.markerId.value == 'driver_location' ||
            m.markerId.value == 'pickup_location');
        _polylines = {
          _buildRidePolyline('driver_to_destination', activeRoutePoints),
        };
        final isPassenger = userController.userModel.value?.userProfile?.role ==
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
      });

      final bounds = boundsFromLatLng(activeRoutePoints);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 48),
      );
    } catch (e) {
      debugPrint('_loadAcceptedRideRoute error: $e');
    }
  }

  void _updateRouteForAnimatedCar(LatLng driverPos) {
    final status = mapOPTController.rideStatusData.value;
    if (status?.ongoingRide != true && status?.startRide != true) return;
    if (_fullRoutePoints.isEmpty || _routeTarget == null) return;

    final now = DateTime.now();
    if (_lastAnimatedRouteUpdateAt != null &&
        now.difference(_lastAnimatedRouteUpdateAt!) <
            const Duration(milliseconds: 100)) {
      return;
    }
    _lastAnimatedRouteUpdateAt = now;
    updatePolylineForDriverPosition(driverPos, allowReroute: false);
  }

  void updatePolylineForDriverPosition(
    LatLng driverPos, {
    bool allowReroute = true,
  }) {
    if (_fullRoutePoints.isEmpty || _routeTarget == null) return;

    final projection = _nearestPointOnRoute(driverPos, _fullRoutePoints);
    final closestDist = projection.distanceMeters;

    if (closestDist > 50 && !allowReroute) return;
    if (closestDist > 50 && !_isReFetchingRoute) {
      _isReFetchingRoute = true;
      reFetchRouteFromDriver(driverPos);
      return;
    }

    final remaining = _fullRoutePoints.sublist(projection.nextPointIndex);
    final routeFromProjection = [projection.point, ...remaining];
    final updatedPoints = closestDist < 0.3
        ? [driverPos, ...remaining]
        : [driverPos, projection.point, ...remaining];
    _fullRoutePoints = routeFromProjection;

    if (!mounted) return;
    setState(() {
      final rideStatus = mapOPTController.rideStatusData.value;
      final bool isPickupPhase =
          rideStatus?.acceptRide == true || rideStatus?.ongoingRide == true;

      _polylines = {
        _buildRidePolyline(
          isPickupPhase ? 'driver_to_pickup' : 'driver_to_destination',
          updatedPoints,
        ),
      };
    });
  }

  ({
    LatLng point,
    int nextPointIndex,
    double distanceMeters,
  }) _nearestPointOnRoute(LatLng position, List<LatLng> route) {
    if (route.length == 1) {
      return (
        point: route.first,
        nextPointIndex: 1,
        distanceMeters: Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          route.first.latitude,
          route.first.longitude,
        ),
      );
    }

    var bestPoint = route.first;
    var bestNextIndex = 1;
    var bestDistance = double.infinity;
    final longitudeScale =
        math.cos(position.latitude * math.pi / 180).abs().clamp(0.01, 1.0);
    final positionX = position.longitude * longitudeScale;
    final positionY = position.latitude;

    for (var i = 0; i < route.length - 1; i++) {
      final start = route[i];
      final end = route[i + 1];
      final startX = start.longitude * longitudeScale;
      final startY = start.latitude;
      final endX = end.longitude * longitudeScale;
      final endY = end.latitude;
      final deltaX = endX - startX;
      final deltaY = endY - startY;
      final segmentLengthSquared = deltaX * deltaX + deltaY * deltaY;
      final rawProgress = segmentLengthSquared == 0
          ? 0.0
          : ((positionX - startX) * deltaX + (positionY - startY) * deltaY) /
              segmentLengthSquared;
      final progress = rawProgress.clamp(0.0, 1.0);
      final projected = LatLng(
        startY + deltaY * progress,
        (startX + deltaX * progress) / longitudeScale,
      );
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        projected.latitude,
        projected.longitude,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = projected;
        bestNextIndex = i + 1;
      }
    }

    return (
      point: bestPoint,
      nextPointIndex: bestNextIndex,
      distanceMeters: bestDistance,
    );
  }

  Future<void> reFetchRouteFromDriver(LatLng driverPos) async {
    final routeGeneration = ++_routeGeneration;
    try {
      if (_routeTarget == null) return;
      final newRoute =
          await DirectionsService.getPolyline(driverPos, _routeTarget!);
      if (routeGeneration == _routeGeneration && newRoute.isNotEmpty) {
        _fullRoutePoints = newRoute;
        updatePolylineForDriverPosition(driverPos);
      }
    } catch (e) {
      debugPrint('_reFetchRouteFromDriver error: $e');
    } finally {
      _isReFetchingRoute = false;
    }
  }

  Polyline _buildRidePolyline(String id, List<LatLng> points) {
    return Polyline(
      polylineId: PolylineId(id),
      points: points,
      color: const Color(0xFF4285F4),
      width: 7,
      jointType: JointType.round,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      zIndex: 2,
    );
  }

  LatLngBounds boundsFromLatLng(List<LatLng> points) {
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
}
