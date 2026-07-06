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
        driverLocation = LatLng(coords[1], coords[0]);
      } else {
        final Position currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        driverLocation = LatLng(
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

      final bounds = boundsFromLatLng(activeRoutePoints);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
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
        driverLocation = LatLng(coords[1], coords[0]);
      } else {
        final Position currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        driverLocation = LatLng(
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

      final bounds = boundsFromLatLng(activeRoutePoints);
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 80),
      );
    } catch (e) {
      debugPrint('_loadAcceptedRideRoute error: $e');
    }
  }

  void updatePolylineForDriverPosition(LatLng driverPos) {
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
      reFetchRouteFromDriver(driverPos);
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

  Future<void> reFetchRouteFromDriver(LatLng driverPos) async {
    try {
      if (_routeTarget == null) return;
      final newRoute =
          await DirectionsService.getPolyline(driverPos, _routeTarget!);
      if (newRoute.isNotEmpty) {
        _fullRoutePoints = newRoute;
        updatePolylineForDriverPosition(driverPos);
      }
    } catch (e) {
      debugPrint('_reFetchRouteFromDriver error: $e');
    } finally {
      _isReFetchingRoute = false;
    }
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
