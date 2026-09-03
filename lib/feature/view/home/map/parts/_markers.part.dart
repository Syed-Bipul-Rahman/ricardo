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
    final currentLat = mapOPTController.currentLatitudePosition?.value;
    final currentLng = mapOPTController.currentLongitudePosition?.value;
    final fallback = currentLat != null && currentLng != null
        ? LatLng(currentLat, currentLng)
        : target;
    final start =
        mapOPTController.animatedCurrentMarkerPosition.value ?? fallback;
    final distance = _distanceBetween(start, target);
    final isStopped = !reportedSpeedMps.isFinite || reportedSpeedMps < 0.5;

    if (isStopped || distance < 0.5) {
      _currentMarkerAnimation?.cancel();
      final snapped = _snapToRoute(target, advanceCursor: true) ?? target;
      mapOPTController.animatedCurrentMarkerSpeedMps.value = 0;
      mapOPTController.animatedCurrentMarkerPosition.value = snapped;
      updatePolylineForDriverPosition(snapped);
      mapOPTController.liveOverlayRevision.value++;
      return;
    }

    final speed = reportedSpeedMps.clamp(0.5, 55.0).toDouble();
    final heading = distance >= 0.2
        ? _bearingBetween(start, target)
        : mapOPTController.animatedCurrentMarkerHeading.value;
    mapOPTController.animatedCurrentMarkerSpeedMps.value = speed;
    unawaited(_ensureCarTravelVisible(start, target));

    _animateMarker(
      from: start,
      to: target,
      durationMs: _travelDurationMs(
        distanceMeters: distance,
        speedMps: speed,
        updateInterval: null,
      ),
      curve: Curves.linear,
      startHeading: mapOPTController.animatedCurrentMarkerHeading.value,
      targetHeading: heading,
      cancelPrevious: () => _currentMarkerAnimation?.cancel(),
      saveTimer: (timer) => _currentMarkerAnimation = timer,
      onFrame: (position, rotation) {
        mapOPTController.animatedCurrentMarkerPosition.value = position;
        mapOPTController.animatedCurrentMarkerHeading.value = rotation;
        mapOPTController.liveOverlayRevision.value++;
        // Route trimming is expensive — do it at sample boundaries, not every frame.
      },
      onComplete: () {
        final snapped = _snapToRoute(target, advanceCursor: true) ?? target;
        updatePolylineForDriverPosition(snapped);
      },
    );
  }

  /// Passenger live-car update from a validated socket sample.
  void _applyLiveDriverSample(LiveDriverLocationSample sample) {
    final target = sample.position;
    final start = mapOPTController.animatedRemoteDriverPosition.value ??
        sample.previousPosition ??
        target;
    final distance = _distanceBetween(start, target);
    final isPassenger = userController.userModel.value?.userProfile?.role ==
        AppConstants.passenger;

    if (_liveLocationDiag) {
      debugPrint(
        '🚗 LIVE sample seq=${sample.sequence} '
        'lat=${target.latitude.toStringAsFixed(6)} '
        'lng=${target.longitude.toStringAsFixed(6)} '
        'speed=${sample.speedMps.toStringAsFixed(2)} '
        'dist=${sample.distanceFromPreviousMeters.toStringAsFixed(1)}m '
        'interval=${sample.intervalFromPrevious?.inMilliseconds ?? -1}ms '
        'dup=${sample.isDuplicate} stopped=${sample.isStopped} '
        'animStartDist=${distance.toStringAsFixed(1)}m',
      );
    }

    mapOPTController.animatedRemoteDriverSpeedMps.value = sample.speedMps;

    // STOP: cancel coasting animation and settle immediately.
    if (sample.isStopped || sample.isDuplicate) {
      _remoteDriverAnimation?.cancel();
      _remoteDriverTarget = target;
      final snapped = _snapToRoute(target, advanceCursor: true) ?? target;
      mapOPTController.animatedRemoteDriverPosition.value = snapped;
      if (sample.headingDegrees > 0 || distance >= 0.2) {
        mapOPTController.animatedRemoteDriverHeading.value =
            sample.headingDegrees;
      }
      if (isPassenger) {
        updatePolylineForDriverPosition(snapped);
      }
      mapOPTController.liveOverlayRevision.value++;
      return;
    }

    final sameTarget = _remoteDriverTarget != null &&
        _distanceBetween(_remoteDriverTarget!, target) < 0.5;
    if (sameTarget && _remoteDriverAnimation?.isActive == true) {
      return;
    }

    final heading = distance >= 0.2
        ? sample.headingDegrees
        : mapOPTController.animatedRemoteDriverHeading.value;
    _remoteDriverTarget = target;
    unawaited(_ensureCarTravelVisible(start, target));

    final durationMs = _travelDurationMs(
      distanceMeters: distance,
      speedMps: sample.speedMps,
      updateInterval: sample.intervalFromPrevious ??
          _liveDriverTracker.lastUpdateInterval,
    );

    if (_liveLocationDiag) {
      debugPrint(
        '🚗 LIVE animate duration=${durationMs}ms '
        'speed=${sample.speedMps.toStringAsFixed(2)} '
        'from=(${start.latitude.toStringAsFixed(5)},${start.longitude.toStringAsFixed(5)}) '
        'to=(${target.latitude.toStringAsFixed(5)},${target.longitude.toStringAsFixed(5)})',
      );
    }

    _animateMarker(
      from: start,
      to: target,
      durationMs: durationMs,
      curve: Curves.linear,
      startHeading: mapOPTController.animatedRemoteDriverHeading.value,
      targetHeading: heading,
      cancelPrevious: () => _remoteDriverAnimation?.cancel(),
      saveTimer: (timer) => _remoteDriverAnimation = timer,
      onFrame: (position, rotation) {
        mapOPTController.animatedRemoteDriverPosition.value = position;
        mapOPTController.animatedRemoteDriverHeading.value = rotation;
        mapOPTController.liveOverlayRevision.value++;
      },
      onComplete: () {
        if (isPassenger) {
          final snapped = _snapToRoute(target, advanceCursor: true) ?? target;
          _updateRouteForAnimatedCar(snapped);
          updatePolylineForDriverPosition(snapped);
        }
        if (_liveLocationDiag) {
          debugPrint('🚗 LIVE animate complete seq=${sample.sequence}');
        }
      },
    );
  }

  void _animateMarker({
    required LatLng from,
    required LatLng to,
    required VoidCallback cancelPrevious,
    required void Function(Timer) saveTimer,
    required void Function(LatLng, double) onFrame,
    VoidCallback? onComplete,
    int? durationMs,
    Curve curve = Curves.easeInOutCubic,
    double startHeading = 0,
    double targetHeading = 0,
  }) {
    cancelPrevious();

    // Prefer the road geometry between the two GPS samples. Path endpoints are
    // route-snapped so sidewalk GPS drift cannot pull the marker off the road.
    final routePath = _routeAnimationPath(from, to);
    final bool hasRoad = _fullRoutePoints.length >= 2;
    final LatLng animFrom;
    final LatLng animTo;
    if (routePath != null && routePath.isNotEmpty) {
      animFrom = routePath.first;
      animTo = routePath.last;
    } else if (hasRoad) {
      animFrom = _snapToRoute(from) ?? (_snapToRoute(to) ?? from);
      animTo = _snapToRoute(to) ?? animFrom;
    } else {
      animFrom = from;
      animTo = to;
    }

    final List<LatLng>? effectivePath =
        (routePath != null && routePath.length >= 2)
            ? routePath
            : (!hasRoad ? <LatLng>[animFrom, animTo] : routePath);

    onFrame(
      animFrom,
      effectivePath != null && effectivePath.length >= 2
          ? _bearingBetween(effectivePath.first, effectivePath[1])
          : startHeading,
    );

    final travelMeters = effectivePath != null && effectivePath.length >= 2
        ? _routePathLengthMeters(effectivePath)
        : Geolocator.distanceBetween(
            animFrom.latitude,
            animFrom.longitude,
            animTo.latitude,
            animTo.longitude,
          );

    // Tiny hop or single on-road hold — settle immediately.
    if (travelMeters < 0.2) {
      onFrame(animTo, targetHeading);
      onComplete?.call();
      return;
    }

    // If we have a road but failed to build a multi-point path, still move
    // along the two snapped road points (same segment) — never raw GPS.
    final List<LatLng> pathForAnim = (effectivePath != null &&
            effectivePath.length >= 2)
        ? effectivePath
        : (hasRoad ? <LatLng>[animFrom, animTo] : <LatLng>[animFrom, animTo]);

    final roadDistance = _routePathLengthMeters(pathForAnim);
    final rawChord = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final int resolvedDurationMs;
    if (durationMs != null) {
      if (roadDistance > 0.2 &&
          rawChord > 0.2 &&
          roadDistance > rawChord * 1.05) {
        final scaled = (durationMs * (roadDistance / rawChord)).round();
        resolvedDurationMs = scaled.clamp(
          math.max(80, durationMs),
          math.max(durationMs, (durationMs * 1.35).round()),
        );
      } else {
        resolvedDurationMs = durationMs;
      }
    } else {
      resolvedDurationMs = _travelDurationMs(
        distanceMeters: roadDistance,
        speedMps: 8.33,
        updateInterval: null,
      );
    }

    if (resolvedDurationMs <= 0) {
      onFrame(animTo, targetHeading);
      onComplete?.call();
      return;
    }

    final startedAt = DateTime.now();
    final headingDelta = ((targetHeading - startHeading + 540) % 360) - 180;

    late final Timer timer;
    // ~20 FPS for Uber-like continuous motion without starving map tiles.
    timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final progress = (elapsed / resolvedDurationMs).clamp(0.0, 1.0);
      final eased = curve.transform(progress);

      LatLng position;
      double rotation;
      if (pathForAnim.length >= 2 && hasRoad) {
        final alongRoute = _positionAlongRoutePath(pathForAnim, eased);
        position = alongRoute.position;
        rotation = alongRoute.bearing;
      } else if (pathForAnim.length >= 2) {
        final alongRoute = _positionAlongRoutePath(pathForAnim, eased);
        position = alongRoute.position;
        rotation = alongRoute.bearing != 0
            ? alongRoute.bearing
            : (startHeading + headingDelta * eased + 360) % 360;
      } else {
        position = animTo;
        rotation = targetHeading;
      }

      // Explicit road lock while a route is active.
      if (hasRoad) {
        position = _snapToRoute(position) ?? position;
      }

      onFrame(position, rotation);
      if (progress >= 1) {
        timer.cancel();
        onComplete?.call();
      }
    });
    saveTimer(timer);
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

  /// Catch-up duration so the marker stays near the live vehicle.
  /// Long intervals used to animate for up to 2.5s — that made the car feel
  /// permanently late vs Uber/Pathao. New samples retarget immediately.
  int _travelDurationMs({
    required double distanceMeters,
    required double speedMps,
    required Duration? updateInterval,
  }) {
    if (distanceMeters < 0.2 || speedMps < 0.15) return 0;

    final fromSpeedMs =
        ((distanceMeters / speedMps.clamp(0.15, 55.0)) * 1000).round();

    final intervalMs = updateInterval?.inMilliseconds;
    final int candidate;
    if (intervalMs != null && intervalMs > 0) {
      // Finish slightly before the next sample so we never trail a full cycle.
      candidate = math.min(fromSpeedMs, (intervalMs * 0.85).round());
    } else {
      candidate = fromSpeedMs;
    }

    // Snappy catch-up window: smooth enough, never multi-second lag.
    return candidate.clamp(80, 550);
  }

  double _distanceBetween(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
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
