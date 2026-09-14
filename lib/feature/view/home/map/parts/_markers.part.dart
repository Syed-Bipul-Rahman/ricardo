part of '../../map_screen.dart';

extension _Markers on _MapScreenState {
  Future<void> initMarkers() async {
    const markerSize = 48.0;
    const configuration = ImageConfiguration(size: Size.square(markerSize));

    customMarker = await BitmapDescriptor.asset(
      configuration,
      "assets/images/passenger_location_marker.png",
      width: markerSize,
      height: markerSize,
    );
    customCarMarker = await BitmapDescriptor.asset(
      configuration,
      "assets/images/car_marker.png",
      width: markerSize,
      height: markerSize,
    );
    customUserMarker = await BitmapDescriptor.asset(
      configuration,
      'assets/images/passenger_marker.png',
      width: markerSize,
      height: markerSize,
    );
    destinationMarker = await BitmapDescriptor.asset(
      configuration,
      'assets/images/destination_marker.png',
      width: markerSize,
      height: markerSize,
    );
    mapOPTController.markerAssetsRevision.value++;
  }

  void _bindVehicleMotionEngines() {
    _selfMotionEngine
      ..displayedPosition =
          mapOPTController.animatedCurrentMarkerPosition.value
      ..displayedHeading =
          mapOPTController.animatedCurrentMarkerHeading.value
      ..alongPath = _positionAlongRoutePath
      ..lookAheadBearing = _lookAheadBearing
      ..isMounted = () {
        return mounted;
      }
      ..onFrame = (position, heading) {
        mapOPTController.animatedCurrentMarkerPosition.value = position;
        mapOPTController.animatedCurrentMarkerHeading.value = heading;
        mapOPTController.animatedCurrentMarkerSpeedMps.value =
            _selfMotionEngine.smoothedSpeedMps;
        mapOPTController.liveOverlayRevision.value++;
        _softFollowCar(position);
      }
      ..onSettled = () {
        final pos = _selfMotionEngine.displayedPosition;
        if (pos != null) updatePolylineForDriverPosition(pos);
      };

    _remoteMotionEngine
      ..displayedPosition =
          mapOPTController.animatedRemoteDriverPosition.value
      ..displayedHeading =
          mapOPTController.animatedRemoteDriverHeading.value
      ..alongPath = _positionAlongRoutePath
      ..lookAheadBearing = _lookAheadBearing
      ..isMounted = () {
        return mounted;
      }
      ..onFrame = (position, heading) {
        mapOPTController.animatedRemoteDriverPosition.value = position;
        mapOPTController.animatedRemoteDriverHeading.value = heading;
        mapOPTController.animatedRemoteDriverSpeedMps.value =
            _remoteMotionEngine.smoothedSpeedMps;
        mapOPTController.remoteVehiclePhase.value =
            _remoteMotionEngine.phase.name;
        mapOPTController.liveOverlayRevision.value++;
        _softFollowCar(position);
      }
      ..onSettled = () {
        final isPassenger =
            userController.userModel.value?.userProfile?.role ==
                AppConstants.passenger;
        final pos = _remoteMotionEngine.displayedPosition;
        if (isPassenger && pos != null) {
          _updateRouteForAnimatedCar(pos);
          updatePolylineForDriverPosition(pos);
        }
      };
  }

  Set<Marker> buildMarkers() {
    final Set<Marker> result = {};
    final markerAssetsReady = mapOPTController.markerAssetsRevision.value > 0;
    final carIcon = markerAssetsReady && customCarMarker != null
        ? customCarMarker!
        : BitmapDescriptor.defaultMarker;

    final currentLat = mapOPTController.currentLatitudePosition?.value ?? 0.0;
    final currentLng = mapOPTController.currentLongitudePosition?.value ?? 0.0;
    final currentPosition =
        mapOPTController.animatedCurrentMarkerPosition.value ??
            LatLng(currentLat, currentLng);
    final rideStatus = mapOPTController.rideStatusData.value;

    final bool isPassenger =
        userController.userModel.value?.userProfile?.role ==
            AppConstants.passenger;

    if (currentLat != 0.0 && currentLng != 0.0) {
      final double heading =
          mapOPTController.animatedCurrentMarkerHeading.value;
      final BitmapDescriptor selfIcon = isPassenger
          ? (markerAssetsReady
              ? (customMarker ?? BitmapDescriptor.defaultMarker)
              : BitmapDescriptor.defaultMarker)
          : carIcon;
      final bool inActiveRide = rideStatus?.acceptRide == true ||
          rideStatus?.ongoingRide == true ||
          rideStatus?.arrivingRide == true ||
          rideStatus?.startRide == true ||
          rideStatus?.completeRide == true;
      final BitmapDescriptor activeIcon = carIcon;

      result.add(
        Marker(
          markerId: const MarkerId('currentPassenger'),
          position: currentPosition,
          icon: isPassenger ? selfIcon : (inActiveRide ? activeIcon : selfIcon),
          rotation: !isPassenger ? heading : 0,
          anchor:
              !isPassenger ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
          flat: !isPassenger,
        ),
      );
    }
    if (isPassenger) {
      final driverCoords = mapOPTController
          .getRideDriverLocation.value?.driverLocation?.coordinates;
      if (driverCoords != null && driverCoords.length >= 2) {
        result.add(Marker(
          markerId: const MarkerId('live_driver'),
          position: mapOPTController.animatedRemoteDriverPosition.value ??
              LatLng(driverCoords[1], driverCoords[0]),
          icon: carIcon,
          rotation: mapOPTController.animatedRemoteDriverHeading.value,
          anchor: const Offset(0.5, 0.5),
          flat: true,
        ));
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
            icon: carIcon,
            onTap: () => showDriverInfoDialog(context, driver, rideController),
          ));
        }
      }
    }

    return result;
  }

  void _animateCurrentMarkerTo(
    LatLng target, {
    required double reportedSpeedMps,
  }) {
    if (_selfMotionEngine.phase == VehicleMotionPhase.arrived &&
        mapOPTController.rideStatusData.value?.completeRide != true) {
      _selfMotionEngine.halt(to: VehicleMotionPhase.idle);
    }

    final currentLat = mapOPTController.currentLatitudePosition?.value;
    final currentLng = mapOPTController.currentLongitudePosition?.value;
    final fallback = currentLat != null && currentLng != null
        ? LatLng(currentLat, currentLng)
        : target;
    final start = _selfMotionEngine.displayedPosition ??
        mapOPTController.animatedCurrentMarkerPosition.value ??
        fallback;

    final hasRoad = _fullRoutePoints.length >= 2;
    final LatLng? snappedTarget =
        hasRoad ? _snapToRoute(target, advanceCursor: true) : null;
    if (hasRoad && snappedTarget == null) {
      if (!_isReFetchingRoute && _routeTarget != null) {
        _isReFetchingRoute = true;
        reFetchRouteFromDriver(target);
      }
      // Off-route: keep moving toward filtered GPS, never teleport onto the old road.
      _selfMotionEngine.observe(
        target: target,
        path: [start, target],
        observedSpeedMps: reportedSpeedMps,
        isStopped: !reportedSpeedMps.isFinite || reportedSpeedMps < 0.5,
        offRoute: true,
      );
      return;
    }
    final roadTarget = snappedTarget ?? target;
    final isStopped = !reportedSpeedMps.isFinite || reportedSpeedMps < 0.5;
    final path = _routeAnimationPath(start, roadTarget) ?? <LatLng>[start, roadTarget];

    unawaited(_ensureCarTravelVisible(start, roadTarget));
    _selfMotionEngine.observe(
      target: roadTarget,
      path: path,
      observedSpeedMps: reportedSpeedMps,
      isStopped: isStopped,
      remainingToDestinationMeters: _remainingRouteMeters(start),
    );
  }

  /// Passenger live-car update from a validated socket sample.
  void _applyLiveDriverSample(LiveDriverLocationSample sample) {
    if (_remoteMotionEngine.phase == VehicleMotionPhase.arrived &&
        mapOPTController.rideStatusData.value?.completeRide != true) {
      _remoteMotionEngine.halt(to: VehicleMotionPhase.idle);
    }

    final rawTarget = sample.position;
    final start = _remoteMotionEngine.displayedPosition ??
        mapOPTController.animatedRemoteDriverPosition.value ??
        sample.previousPosition ??
        rawTarget;
    final isPassenger = userController.userModel.value?.userProfile?.role ==
        AppConstants.passenger;
    final hasRoad = _fullRoutePoints.length >= 2;

    final LatLng? snappedTarget =
        hasRoad ? _snapToRoute(rawTarget, advanceCursor: true) : null;
    if (hasRoad && snappedTarget == null) {
      if (!_isReFetchingRoute && _routeTarget != null) {
        _isReFetchingRoute = true;
        reFetchRouteFromDriver(rawTarget);
      }
      _remoteMotionEngine.observe(
        target: rawTarget,
        path: [start, rawTarget],
        observedSpeedMps: sample.speedMps,
        isStopped: sample.isStopped || sample.isDuplicate,
        offRoute: true,
      );
      return;
    }
    final target = snappedTarget ?? rawTarget;

    if (_liveLocationDiag) {
      debugPrint(
        '🚗 LIVE sample seq=${sample.sequence} '
        'lat=${target.latitude.toStringAsFixed(6)} '
        'lng=${target.longitude.toStringAsFixed(6)} '
        'speed=${sample.speedMps.toStringAsFixed(2)} '
        'dist=${sample.distanceFromPreviousMeters.toStringAsFixed(1)}m '
        'interval=${sample.intervalFromPrevious?.inMilliseconds ?? -1}ms '
        'dup=${sample.isDuplicate} stopped=${sample.isStopped}',
      );
    }

    mapOPTController.animatedRemoteDriverSpeedMps.value = sample.speedMps;

    final path = _routeAnimationPath(start, target) ?? <LatLng>[start, target];
    unawaited(_ensureCarTravelVisible(start, target));
    _remoteMotionEngine.observe(
      target: target,
      path: path,
      observedSpeedMps: sample.speedMps,
      isStopped: sample.isStopped || sample.isDuplicate,
      remainingToDestinationMeters: isPassenger ? _remainingRouteMeters(start) : null,
    );
  }

  void _haltVehicleMotion({
    VehicleMotionPhase phase = VehicleMotionPhase.arrived,
  }) {
    _selfMotionEngine.halt(to: phase);
    _remoteMotionEngine.halt(to: phase);
    _remoteDriverTarget = null;
    mapOPTController.remoteVehiclePhase.value = phase.name;
  }

  double _routePathLengthMeters(List<LatLng> path) {
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      total += Geolocator.distanceBetween(
        path[i].latitude,
        path[i].longitude,
        path[i + 1].latitude,
        path[i + 1].longitude,
      );
    }
    return total;
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final fromLat = from.latitude * math.pi / 180;
    final toLat = to.latitude * math.pi / 180;
    final lngDelta = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(lngDelta) * math.cos(toLat);
    final x = math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(lngDelta);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
