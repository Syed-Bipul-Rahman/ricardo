import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Visual motion phase for the live car marker. Distinct from last GPS.
enum VehicleMotionPhase { idle, moving, stopping, stopped, arrived }

typedef VehiclePathPose = ({LatLng position, double bearing});
typedef VehicleAlongPath = VehiclePathPose Function(
  List<LatLng> path,
  double progress,
);
typedef VehicleLookAhead = double Function(
  List<LatLng> path,
  double progress,
  double lookAheadMeters,
);
typedef VehicleFrameCallback = void Function(LatLng position, double heading);

/// One-loop chase interpolator.
///
/// GPS/socket samples only replace [latestTargetPosition] and the remaining
/// path from the **current visual pose**. A single vsync callback advances
/// the pose toward that target. There is no duration clip, no queue, and no
/// second timer. Settles at the latest known coordinate when nothing newer
/// arrives — it does not invent motion.
class VehicleMotionEngine {
  VehicleMotionEngine({this.smoothObservedSpeed = true});

  static const double stoppedSpeedMps = 0.5;
  static const double settleDistanceMeters = 0.45;
  static const double noiseTargetMeters = 0.7;
  static const double snapJumpMeters = 80;

  /// `car_marker.png` faces north (windshield at top). Marker.rotation is
  /// clockwise from north, so no extra offset.
  static const double carIconRotationOffset = 0;

  /// When false, [observe] treats [observedSpeedMps] as already smoothed.
  final bool smoothObservedSpeed;

  VehicleAlongPath? alongPath;
  VehicleLookAhead? lookAheadBearing;
  VehicleFrameCallback? onFrame;
  void Function()? onSettled;
  bool Function()? isMounted;

  VehicleMotionPhase phase = VehicleMotionPhase.idle;
  int generation = 0;

  LatLng? displayedPosition;
  double displayedHeading = 0;
  double smoothedSpeedMps = 0;

  LatLng? latestTargetPosition;
  double latestTargetRotation = 0;
  DateTime? lastLocationTimestamp;

  List<LatLng> _path = const [];
  double _distanceAlongMeters = 0;
  double _pathLengthMeters = 0;
  double _travelMps = 0;
  bool _stopping = false;
  bool _offRoute = false;
  LatLng? _pendingTarget;
  List<LatLng>? _pendingPath;
  bool _pendingStop = false;
  double? _pendingHeading;
  bool _frameScheduled = false;
  Duration? _lastFrameStamp;

  void observe({
    required LatLng target,
    required List<LatLng> path,
    required double observedSpeedMps,
    required bool isStopped,
    bool offRoute = false,
    double? remainingToDestinationMeters,
    Duration? sampleInterval,
    double? observedHeading,
  }) {
    if (phase == VehicleMotionPhase.arrived) return;

    final now = DateTime.now();
    final previousTarget = latestTargetPosition;
    final previousAt = lastLocationTimestamp;
    lastLocationTimestamp = now;
    latestTargetPosition = target;

    _offRoute = offRoute;
    final interval = sampleInterval ??
        (previousAt == null ? null : now.difference(previousAt));
    _applyRealSpeed(
      observed: observedSpeedMps,
      isStopped: isStopped,
      gpsHopMeters:
          previousTarget == null ? 0 : _distance(previousTarget, target),
      sampleInterval: interval,
    );

    final from = displayedPosition;
    double? movementBearing;
    if (from != null && _distance(from, target) >= 1.0) {
      movementBearing = _bearing(from, target);
    }
    final resolvedHeading = resolveTravelHeading(
      reported: observedHeading,
      speedMps: smoothedSpeedMps,
      isStopped: isStopped,
      movementBearing: movementBearing,
      fallback: displayedHeading,
    );
    latestTargetRotation = resolvedHeading;

    if (!isStopped && from != null) {
      final visualGap = _distance(from, target);
      if (visualGap < settleDistanceMeters) return;
      if (previousTarget != null &&
          visualGap < 1.5 &&
          _distance(previousTarget, target) < noiseTargetMeters) {
        return;
      }
    }

    List<LatLng> nextPath = path;
    if (nextPath.length < 2) {
      nextPath = [from ?? target];
    }

    _pendingTarget = target;
    _pendingPath = nextPath;
    _pendingStop = isStopped || smoothedSpeedMps < stoppedSpeedMps;
    _pendingHeading = resolvedHeading;

    _applyPendingIfAny();
    _scheduleFrame();
  }

  void halt({VehicleMotionPhase to = VehicleMotionPhase.arrived}) {
    generation++;
    _frameScheduled = false;
    _lastFrameStamp = null;
    _pendingTarget = null;
    _pendingPath = null;
    _pendingStop = false;
    _pendingHeading = null;
    _path = const [];
    _distanceAlongMeters = 0;
    _pathLengthMeters = 0;
    _travelMps = 0;
    _stopping = false;
    _offRoute = false;
    smoothedSpeedMps = 0;
    latestTargetPosition = null;
    lastLocationTimestamp = null;
    phase = to;
  }

  void reset() {
    halt(to: VehicleMotionPhase.idle);
    displayedPosition = null;
    displayedHeading = 0;
    latestTargetRotation = 0;
  }

  void dispose() {
    halt(to: VehicleMotionPhase.idle);
    alongPath = null;
    lookAheadBearing = null;
    onFrame = null;
    onSettled = null;
    isMounted = null;
  }

  /// Marker speed is the real car speed: GPS `speed` when present, otherwise
  /// distance between the last two real points divided by elapsed time.
  void _applyRealSpeed({
    required double observed,
    required bool isStopped,
    required double gpsHopMeters,
    required Duration? sampleInterval,
  }) {
    final intervalSec = sampleInterval == null
        ? 0.0
        : sampleInterval.inMilliseconds / 1000.0;
    final implied = (intervalSec >= 0.05 && gpsHopMeters >= 0.5)
        ? gpsHopMeters / intervalSec
        : 0.0;

    if (observed.isFinite && observed >= stoppedSpeedMps) {
      smoothedSpeedMps = observed;
      return;
    }
    if (implied >= stoppedSpeedMps) {
      smoothedSpeedMps = implied;
      return;
    }
    if (isStopped || gpsHopMeters < settleDistanceMeters) {
      smoothedSpeedMps = 0;
    }
  }

  void _applyPendingIfAny() {
    final pendingPath = _pendingPath;
    final pendingTarget = _pendingTarget;
    if (pendingPath == null || pendingTarget == null) return;
    _pendingPath = null;
    _pendingTarget = null;
    var stopping = _pendingStop;
    _pendingStop = false;
    final pendingHeading = _pendingHeading;
    _pendingHeading = null;

    final from = displayedPosition ?? pendingPath.first;
    var path = List<LatLng>.from(pendingPath);
    if (path.isEmpty) {
      path = [from, pendingTarget];
    } else if (!_pointsEqual(path.first, from) &&
        _distance(from, path.first) > 2) {
      path.insert(0, from);
    }

    if (path.length < 2) {
      if (stopping) {
        _settle(
          path.isEmpty ? pendingTarget : path.last,
          VehicleMotionPhase.stopped,
        );
      } else if (pendingHeading != null) {
        displayedHeading = pendingHeading;
        latestTargetRotation = pendingHeading;
        displayedPosition = displayedPosition ??
            (path.isEmpty ? pendingTarget : path.last);
        _emitFrame();
      }
      _path = const [];
      _pathLengthMeters = 0;
      _distanceAlongMeters = 0;
      return;
    }

    var remaining = pathLengthMeters(path);
    if (remaining < settleDistanceMeters) {
      _settle(
        path.last,
        stopping ? VehicleMotionPhase.stopped : VehicleMotionPhase.moving,
      );
      return;
    }

    // Do not animate a huge leftover polyline for several seconds. Latest GPS
    // is the target; if the road path is far longer than the hop, go direct.
    final straight = _distance(from, pendingTarget);
    if (remaining > math.max(straight * 2.0, 25.0)) {
      path = [from, pendingTarget];
      remaining = straight;
    }

    // Impossible / outlier jump: snap to the latest valid point.
    if (remaining > snapJumpMeters) {
      _settle(
        pendingTarget,
        stopping ? VehicleMotionPhase.stopped : VehicleMotionPhase.moving,
      );
      return;
    }

    if (stopping && smoothedSpeedMps < stoppedSpeedMps) {
      _settle(pendingTarget, VehicleMotionPhase.stopped);
      return;
    }

    displayedPosition ??= path.first;
    if (pendingHeading != null) {
      latestTargetRotation = pendingHeading;
    }
    _path = path;
    _pathLengthMeters = remaining;
    _distanceAlongMeters = 0;
    _stopping = stopping;
    _travelMps = smoothedSpeedMps;
    phase = stopping ? VehicleMotionPhase.stopping : VehicleMotionPhase.moving;
  }

  void _scheduleFrame() {
    if (_frameScheduled) return;
    if (phase == VehicleMotionPhase.arrived) return;
    _frameScheduled = true;
    final gen = generation;
    SchedulerBinding.instance.scheduleFrameCallback((stamp) {
      _frameScheduled = false;
      if (gen != generation) return;
      _onFrame(stamp);
    });
  }

  void _onFrame(Duration stamp) {
    if (isMounted != null && isMounted!() == false) {
      halt(to: VehicleMotionPhase.idle);
      return;
    }

    final last = _lastFrameStamp;
    _lastFrameStamp = stamp;
    var dt = last == null ? 0.016 : (stamp - last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.05) dt = 0.016;

    _applyPendingIfAny();

    if (_path.length < 2 || _pathLengthMeters < settleDistanceMeters) {
      if (_pendingPath != null) {
        _scheduleFrame();
        return;
      }
      final hold = displayedPosition;
      if (_stopping && hold != null) {
        _settle(hold, VehicleMotionPhase.stopped);
      }
      return;
    }

    final remaining = _pathLengthMeters - _distanceAlongMeters;
    if (remaining <= settleDistanceMeters) {
      final end = _path.last;
      displayedPosition = end;
      if (!_stopping && smoothedSpeedMps >= stoppedSpeedMps) {
        displayedHeading = _bearing(_path[_path.length - 2], end);
      }
      _emitFrame();
      _path = const [];
      _pathLengthMeters = 0;
      _distanceAlongMeters = 0;
      if (_stopping) {
        _settle(end, VehicleMotionPhase.stopped);
      } else {
        phase = VehicleMotionPhase.moving;
        onSettled?.call();
      }
      return;
    }

    _distanceAlongMeters =
        math.min(_pathLengthMeters, _distanceAlongMeters + _travelMps * dt);
    final t = (_distanceAlongMeters / _pathLengthMeters).clamp(0.0, 1.0);
    final along = alongPath?.call(_path, t) ?? _fallbackAlong(_path, t);
    displayedPosition = along.position;

    if (!_stopping && _travelMps >= stoppedSpeedMps) {
      final desired = _offRoute ? latestTargetRotation : along.bearing;
      final hopSec = _travelMps > 0.01
          ? math.max(remaining / _travelMps, 0.05)
          : 0.2;
      final headingDelta =
          shortestAngleDelta(displayedHeading, desired).abs();
      displayedHeading = stepHeading(
        displayedHeading,
        desired,
        headingDelta * (dt / hopSec),
      );
    }

    _emitFrame();
    _scheduleFrame();
  }

  void _emitFrame() {
    final pos = displayedPosition;
    if (pos == null) return;
    onFrame?.call(
      pos,
      (displayedHeading + carIconRotationOffset + 360) % 360,
    );
  }

  void _settle(LatLng at, VehicleMotionPhase to) {
    generation++;
    displayedPosition = at;
    smoothedSpeedMps = 0;
    _travelMps = 0;
    phase = to;
    _path = const [];
    _pathLengthMeters = 0;
    _distanceAlongMeters = 0;
    _pendingTarget = null;
    _pendingPath = null;
    _pendingStop = false;
    _pendingHeading = null;
    _frameScheduled = false;
    _lastFrameStamp = null;
    _stopping = false;
    _emitFrame();
    onSettled?.call();
  }

  static double lerpHeading(double from, double to, double t) {
    final delta = shortestAngleDelta(from, to);
    return (from + delta * t.clamp(0.0, 1.0) + 360) % 360;
  }

  static double resolveTravelHeading({
    required double? reported,
    required double speedMps,
    required bool isStopped,
    required double? movementBearing,
    required double fallback,
  }) {
    if (isStopped || speedMps < stoppedSpeedMps) {
      return fallback;
    }

    final reportedOk = reported != null && reported.isFinite && reported >= 0;
    if (reportedOk) {
      final heading = (reported % 360 + 360) % 360;
      if (heading == 0 && movementBearing != null) {
        final delta = shortestAngleDelta(0, movementBearing).abs();
        if (delta > 45) return (movementBearing + 360) % 360;
      }
      return heading;
    }

    if (movementBearing != null) {
      return (movementBearing + 360) % 360;
    }
    return fallback;
  }

  static double lookAheadMeters(double speedMps) {
    return (0.8 * speedMps).clamp(6.0, 22.0);
  }

  static double shortestAngleDelta(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  static double stepHeading(double current, double target, double maxStep) {
    final delta = shortestAngleDelta(current, target);
    if (delta.abs() <= maxStep) return (target + 360) % 360;
    return (current + delta.sign * maxStep + 360) % 360;
  }

  static double pathLengthMeters(List<LatLng> path) {
    var total = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      total += _distance(path[i], path[i + 1]);
    }
    return total;
  }

  static VehiclePathPose _fallbackAlong(List<LatLng> path, double progress) {
    if (path.length < 2) {
      return (position: path.first, bearing: 0);
    }
    final total = pathLengthMeters(path);
    if (total < 0.01) {
      return (
        position: path.last,
        bearing: _bearing(path[path.length - 2], path.last),
      );
    }
    final targetDistance = progress.clamp(0.0, 1.0) * total;
    var covered = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      final seg = _distance(path[i], path[i + 1]);
      if (covered + seg >= targetDistance) {
        final t = seg < 0.001 ? 0.0 : (targetDistance - covered) / seg;
        return (
          position: LatLng(
            path[i].latitude + (path[i + 1].latitude - path[i].latitude) * t,
            path[i].longitude + (path[i + 1].longitude - path[i].longitude) * t,
          ),
          bearing: _bearing(path[i], path[i + 1]),
        );
      }
      covered += seg;
    }
    return (
      position: path.last,
      bearing: _bearing(path[path.length - 2], path.last),
    );
  }

  static double _bearing(LatLng from, LatLng to) {
    final fromLat = from.latitude * math.pi / 180;
    final toLat = to.latitude * math.pi / 180;
    final lngDelta = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(lngDelta) * math.cos(toLat);
    final x = math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(lngDelta);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  static double _distance(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  static bool _pointsEqual(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 1e-9 &&
        (a.longitude - b.longitude).abs() < 1e-9;
  }
}
