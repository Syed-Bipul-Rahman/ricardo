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
    final speed = reportedSpeedMps.isFinite && reportedSpeedMps > 0.5
        ? reportedSpeedMps.clamp(0.5, 55.0).toDouble()
        : 8.33;
    final heading = distance >= 0.2
        ? _bearingBetween(start, target)
        : mapOPTController.animatedCurrentMarkerHeading.value;
    mapOPTController.animatedCurrentMarkerSpeedMps.value = speed;
    unawaited(_ensureCarTravelVisible(start, target));

    _animateMarker(
      from: start,
      to: target,
      durationMs: _travelDurationMs(distance, speed),
      curve: Curves.linear,
      startHeading: mapOPTController.animatedCurrentMarkerHeading.value,
      targetHeading: heading,
      cancelPrevious: () => _currentMarkerAnimation?.cancel(),
      saveTimer: (timer) => _currentMarkerAnimation = timer,
      onFrame: (position, rotation) {
        _updateRouteForAnimatedCar(position);
        mapOPTController.animatedCurrentMarkerPosition.value = position;
        mapOPTController.animatedCurrentMarkerHeading.value = rotation;
      },
      onComplete: () => updatePolylineForDriverPosition(target),
    );
  }

  void _animateRemoteDriverTo(LatLng target) {
    final coords = mapOPTController
        .getRideDriverLocation.value?.driverLocation?.coordinates;
    final fallback = coords != null && coords.length >= 2
        ? LatLng(coords[1], coords[0])
        : target;
    final start =
        mapOPTController.animatedRemoteDriverPosition.value ?? fallback;
    final distance = _distanceBetween(start, target);

    // Same as the driver GPS marker: ignore sub-meter jitter, and do not
    // restart an in-flight animation toward the same point (socket polls
    // often repeat the last coordinate).
    final sameTarget = _remoteDriverTarget != null &&
        _distanceBetween(_remoteDriverTarget!, target) < 0.5;
    if (distance < 0.5 ||
        (sameTarget && _remoteDriverAnimation?.isActive == true)) {
      if (mapOPTController.animatedRemoteDriverPosition.value == null) {
        mapOPTController.animatedRemoteDriverPosition.value =
            _snapToRoute(target) ?? target;
      }
      return;
    }

    final speed = _remoteDriverSpeedMps(fallback, target);
    final heading = distance >= 0.2
        ? _bearingBetween(start, target)
        : mapOPTController.animatedRemoteDriverHeading.value;
    mapOPTController.animatedRemoteDriverSpeedMps.value = speed;
    _remoteDriverTarget = target;
    unawaited(_ensureCarTravelVisible(start, target));
    final isPassenger = userController.userModel.value?.userProfile?.role ==
        AppConstants.passenger;

    _animateMarker(
      from: start,
      to: target,
      durationMs: _travelDurationMs(distance, speed),
      curve: Curves.linear,
      startHeading: mapOPTController.animatedRemoteDriverHeading.value,
      targetHeading: heading,
      cancelPrevious: () => _remoteDriverAnimation?.cancel(),
      saveTimer: (timer) => _remoteDriverAnimation = timer,
      onFrame: (position, rotation) {
        if (isPassenger) _updateRouteForAnimatedCar(position);
        mapOPTController.animatedRemoteDriverPosition.value = position;
        mapOPTController.animatedRemoteDriverHeading.value = rotation;
      },
      onComplete:
          isPassenger ? () => updatePolylineForDriverPosition(target) : null,
    );
  }

  /// Derive a GPS-like speed so the passenger car interpolates the same way
  /// the driver car does from `Position.speed`. Burst/duplicate socket
  /// samples are ignored so the marker does not teleport.
  double _remoteDriverSpeedMps(LatLng previousSocket, LatLng target) {
    final previousSpeed = mapOPTController.animatedRemoteDriverSpeedMps.value;
    final lastUpdate = mapOPTController.lastDriverLocationSocketAt.value;
    final intervalMs = lastUpdate == null
        ? 1000
        : DateTime.now().difference(lastUpdate).inMilliseconds;
    final sampleDistance = _distanceBetween(previousSocket, target);
    final hasCleanSample = intervalMs >= 800 && sampleDistance >= 3;
    if (hasCleanSample) {
      final measured =
          (sampleDistance / (intervalMs / 1000)).clamp(0.5, 55.0).toDouble();
      if (previousSpeed > 0.5) {
        return previousSpeed * 0.6 + measured * 0.4;
      }
      return measured;
    }
    if (previousSpeed > 0.5) return previousSpeed;
    return 8.33;
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
    final LatLng animFrom;
    final LatLng animTo;
    if (routePath != null && routePath.isNotEmpty) {
      animFrom = routePath.first;
      animTo = routePath.last;
    } else {
      // No usable route segment — still snap onto the road when possible so
      // the marker never intentionally sits on a sidewalk GPS sample.
      animFrom = _snapToRoute(from) ?? from;
      animTo = _snapToRoute(to) ?? to;
    }

    onFrame(
      animFrom,
      routePath != null && routePath.length >= 2
          ? _bearingBetween(routePath.first, routePath[1])
          : startHeading,
    );

    final chordDistance = Geolocator.distanceBetween(
      animFrom.latitude,
      animFrom.longitude,
      animTo.latitude,
      animTo.longitude,
    );
    if (chordDistance < 0.2) {
      onFrame(animTo, targetHeading);
      onComplete?.call();
      return;
    }

    // Preserve caller wall-clock timing on straight roads. Around turns the
    // road arc is longer than the GPS chord — scale duration so the marker
    // keeps the same speed instead of racing the short sidewalk chord.
    final roadDistance = routePath != null && routePath.length >= 2
        ? _routePathLengthMeters(routePath)
        : chordDistance;
    final rawChord = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final int resolvedDurationMs;
    if (durationMs != null) {
      if (routePath != null &&
          roadDistance > 0.2 &&
          rawChord > 0.2 &&
          roadDistance > rawChord * 1.05) {
        resolvedDurationMs =
            (durationMs * (roadDistance / rawChord)).clamp(250, 30000).round();
      } else {
        resolvedDurationMs = durationMs;
      }
    } else {
      resolvedDurationMs = _travelDurationMs(roadDistance, 8.33);
    }
    final startedAt = DateTime.now();
    final headingDelta = ((targetHeading - startHeading + 540) % 360) - 180;

    late final Timer timer;
    // Native map overlays are expensive to update. At driving speeds, 20 FPS
    // remains smooth while leaving enough frame time for map gestures/tiles.
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
      if (routePath != null && routePath.length >= 2) {
        final alongRoute = _positionAlongRoutePath(routePath, eased);
        position = alongRoute.position;
        rotation = alongRoute.bearing;
      } else if (routePath != null && routePath.length == 1) {
        position = routePath.first;
        rotation = targetHeading;
      } else {
        position = LatLng(
          animFrom.latitude + (animTo.latitude - animFrom.latitude) * eased,
          animFrom.longitude +
              (animTo.longitude - animFrom.longitude) * eased,
        );
        rotation = (startHeading + headingDelta * eased + 360) % 360;
      }

      // Explicit road lock: never emit a sidewalk/off-road coordinate while a
      // route is active. Turns must stay on the drivable path.
      position = _snapToRoute(position) ?? position;

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

  int _travelDurationMs(double distanceMeters, double speedMps) {
    if (distanceMeters < 0.2) return 0;
    final safeSpeed = speedMps.clamp(0.5, 55.0);
    return ((distanceMeters / safeSpeed) * 1000).clamp(250, 30000).round();
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
