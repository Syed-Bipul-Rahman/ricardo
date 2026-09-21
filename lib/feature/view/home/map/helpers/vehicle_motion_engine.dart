import 'dart:async';
import 'dart:math' as math;

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

/// Frontend-only interpolator: GPS observations retarget a displayed pose.
///
/// One source of truth: [displayedPosition] (visual) chases
/// [latestTargetPosition]. New samples never finish an old segment first —
/// they replace the remaining path from the current visual pose.
///
/// Duration is **not** the physical travel time of the visual gap. Animating
/// a lagged gap at real speed makes lag accumulate to ~maxDuration (previously
/// 4s). Duration is the sample interval, with a short catch-up cap when the
/// visual pose is behind the latest GPS.
class VehicleMotionEngine {
  VehicleMotionEngine({this.smoothObservedSpeed = true});

  static const int frameMs = 50;
  static const double speedAlpha = 0.35;
  static const double startAlpha = 0.55;
  static const double stoppedSpeedMps = 0.5;
  static const int minDurationMs = 60;

  /// Catch-up ceiling. Must stay near one GPS interval so lag cannot stack.
  static const int maxDurationMs = 650;
  static const int maxStopDurationMs = 280;
  static const int maxJumpDurationMs = 420;
  static const int maxOnTrackDurationMs = 550;
  static const double minSpeedForDuration = 1.0;
  static const double arrivalProximityMeters = 12;
  static const double settleDistanceMeters = 0.6;
  static const double noiseTargetMeters = 0.7;
  static const double largeJumpMeters = 40;
  static const double catchUpOverrideMeters = 3.0;

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

  /// Latest validated GPS/socket target the visual pose is chasing.
  LatLng? latestTargetPosition;
  DateTime? lastLocationTimestamp;

  List<LatLng> _path = const [];
  DateTime? _pathStartedAt;
  int _durationMs = 0;
  bool _easeOut = false;
  LatLng? _pendingTarget;
  List<LatLng>? _pendingPath;
  bool _pendingStop = false;
  int _pendingIntervalMs = 400;
  double? _pendingHeading;
  bool _offRoute = false;
  Timer? _timer;
  double _headingFrom = 0;
  double _headingTo = 0;

  /// Latest desired travel heading the visual rotation is chasing.
  double latestTargetRotation = 0;

  /// `car_marker.png` faces north (windshield toward top of the image).
  /// GoogleMap [Marker.rotation] is clockwise from north, so no extra offset.
  static const double carIconRotationOffset = 0;

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
    final inferredIntervalMs = lastLocationTimestamp == null
        ? 400
        : now.difference(lastLocationTimestamp!).inMilliseconds.clamp(80, 2000);
    final intervalMs = sampleInterval == null
        ? inferredIntervalMs
        : sampleInterval.inMilliseconds.clamp(80, 2000);
    lastLocationTimestamp = now;
    final previousTarget = latestTargetPosition;
    latestTargetPosition = target;

    _offRoute = offRoute;
    _applySpeed(observedSpeedMps, forceZero: isStopped);

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

    if (remainingToDestinationMeters != null &&
        remainingToDestinationMeters < arrivalProximityMeters &&
        (isStopped || smoothedSpeedMps < stoppedSpeedMps)) {
      _settle(
        path.length >= 2 ? path.last : (displayedPosition ?? target),
        VehicleMotionPhase.stopped,
      );
      return;
    }

    // Ignore GPS noise only when the visual pose is already near the latest
    // point. Never drop a sample while still catching up.
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
      final start = from ?? target;
      // A one-point path means "hold on the road" (e.g. GPS projected backward).
      // Do not invent a straight chord to the GPS target — that cuts corners.
      nextPath = [start];
    }

    _pendingTarget = target;
    _pendingPath = nextPath;
    _pendingStop = isStopped || smoothedSpeedMps < stoppedSpeedMps;
    _pendingIntervalMs = intervalMs;
    _pendingHeading = resolvedHeading;

    // Retarget immediately from the current visual pose. Waiting for the
    // next timer tick (or finishing the old segment) is what stacked lag.
    _applyPendingIfAny();
    if (_path.length >= 2 && _pathStartedAt != null) {
      _startTimer();
    }
  }

  void halt({VehicleMotionPhase to = VehicleMotionPhase.arrived}) {
    generation++;
    _timer?.cancel();
    _timer = null;
    _pendingTarget = null;
    _pendingPath = null;
    _pendingStop = false;
    _pendingIntervalMs = 400;
    _pendingHeading = null;
    _path = const [];
    _pathStartedAt = null;
    _durationMs = 0;
    _easeOut = false;
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

  void _applySpeed(double observed, {required bool forceZero}) {
    if (forceZero || !observed.isFinite || observed < stoppedSpeedMps) {
      smoothedSpeedMps = 0;
      return;
    }
    final raw = observed.clamp(0.0, 55.0);
    if (!smoothObservedSpeed) {
      smoothedSpeedMps = raw;
      return;
    }
    if (smoothedSpeedMps < stoppedSpeedMps) {
      smoothedSpeedMps = startAlpha * raw;
    } else {
      smoothedSpeedMps = speedAlpha * raw + (1 - speedAlpha) * smoothedSpeedMps;
    }
    if (smoothedSpeedMps < stoppedSpeedMps) smoothedSpeedMps = 0;
  }

  void _applyPendingIfAny() {
    final pendingPath = _pendingPath;
    final pendingTarget = _pendingTarget;
    if (pendingPath == null || pendingTarget == null) return;
    _pendingPath = null;
    _pendingTarget = null;
    var stopping = _pendingStop;
    _pendingStop = false;
    final intervalMs = _pendingIntervalMs;
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
        _settle(path.isEmpty ? pendingTarget : path.last,
            VehicleMotionPhase.stopped);
      } else {
        _path = const [];
        _pathStartedAt = null;
        if (pendingHeading != null) {
          displayedHeading = pendingHeading;
          latestTargetRotation = pendingHeading;
        }
        final hold =
            displayedPosition ?? (path.isEmpty ? pendingTarget : path.last);
        displayedPosition = hold;
        onFrame?.call(
          hold,
          (displayedHeading + carIconRotationOffset + 360) % 360,
        );
      }
      return;
    }

    final remaining = pathLengthMeters(path);
    if (remaining < settleDistanceMeters) {
      _settle(
        path.last,
        stopping ? VehicleMotionPhase.stopped : VehicleMotionPhase.moving,
      );
      return;
    }

    // A duplicate/stopped sample must not freeze the marker mid-catch-up.
    if (stopping && remaining > catchUpOverrideMeters) {
      stopping = false;
    }

    if (displayedPosition == null && path.length >= 2) {
      displayedHeading = pendingHeading ??
          alongPath?.call(path, 0).bearing ??
          displayedHeading;
    }
    displayedPosition ??= path.first;
    _headingFrom = displayedHeading;
    final segmentBearing =
        alongPath?.call(path, 0).bearing ?? _bearing(path.first, path[1]);
    _headingTo =
        stopping ? displayedHeading : (pendingHeading ?? segmentBearing);
    latestTargetRotation = _headingTo;
    _path = path;
    _easeOut = stopping;
    phase = stopping ? VehicleMotionPhase.stopping : VehicleMotionPhase.moving;
    _durationMs = durationMsFor(
      remainingMeters: remaining,
      speedMps: stopping
          ? math.max(smoothedSpeedMps, minSpeedForDuration)
          : smoothedSpeedMps,
      sampleIntervalMs: intervalMs,
      stopping: stopping,
    );
    _pathStartedAt = DateTime.now();
  }

  void _startTimer() {
    if (_timer?.isActive == true) return;
    final gen = generation;
    _timer = Timer.periodic(const Duration(milliseconds: frameMs), (timer) {
      if (gen != generation) {
        timer.cancel();
        return;
      }
      if (isMounted != null && isMounted!() == false) {
        halt(to: VehicleMotionPhase.idle);
        return;
      }

      _applyPendingIfAny();

      if (_path.length < 2 || _pathStartedAt == null || _durationMs <= 0) {
        if (_pendingPath != null) return;
        final hold =
            displayedPosition ?? (_path.isNotEmpty ? _path.last : null);
        if (phase == VehicleMotionPhase.stopping && hold != null) {
          _settle(hold, VehicleMotionPhase.stopped);
          return;
        }
        timer.cancel();
        _timer = null;
        return;
      }

      final elapsed = DateTime.now().difference(_pathStartedAt!).inMilliseconds;
      var t = (elapsed / _durationMs).clamp(0.0, 1.0);
      if (_easeOut) t = _easeOutCubic(t);

      final along = alongPath?.call(_path, t) ?? _fallbackAlong(_path, t);
      displayedPosition = along.position;
      if (!(_easeOut || smoothedSpeedMps < stoppedSpeedMps)) {
        if (_offRoute) {
          displayedHeading = lerpHeading(_headingFrom, _headingTo, t);
        } else {
          final desired = along.bearing;
          final turnDelta = shortestAngleDelta(displayedHeading, desired).abs();
          final maxStep = turnDelta > 60
              ? 20.0
              : turnDelta > 25
                  ? 14.0
                  : 10.0;
          displayedHeading = stepHeading(displayedHeading, desired, maxStep);
        }
      }

      onFrame?.call(
        displayedPosition!,
        (displayedHeading + carIconRotationOffset + 360) % 360,
      );

      if (elapsed >= _durationMs) {
        displayedPosition = _path.last;
        displayedHeading = _headingTo;
        onFrame?.call(
          displayedPosition!,
          (displayedHeading + carIconRotationOffset + 360) % 360,
        );
        if (phase == VehicleMotionPhase.stopping || _easeOut) {
          _settle(displayedPosition!, VehicleMotionPhase.stopped);
          return;
        }
        _path = const [];
        _pathStartedAt = null;
        if (_pendingPath == null) {
          timer.cancel();
          _timer = null;
          onSettled?.call();
        }
      }
    });
  }

  void _settle(LatLng at, VehicleMotionPhase to) {
    generation++;
    displayedPosition = at;
    smoothedSpeedMps = 0;
    phase = to;
    _path = const [];
    _pathStartedAt = null;
    _pendingTarget = null;
    _pendingPath = null;
    _pendingStop = false;
    _pendingHeading = null;
    _timer?.cancel();
    _timer = null;
    onFrame?.call(
      at,
      (displayedHeading + carIconRotationOffset + 360) % 360,
    );
    onSettled?.call();
  }

  /// Adaptive duration: reach the *latest* target within about one sample
  /// interval. Physical travel time of a lagged gap is never used as duration
  /// — that is what created the ~3s chase.
  static int durationMsFor({
    required double remainingMeters,
    required double speedMps,
    int? sampleIntervalMs,
    bool stopping = false,
  }) {
    if (remainingMeters < settleDistanceMeters) return 0;

    final interval = (sampleIntervalMs ?? 400).clamp(minDurationMs, 1200);

    if (stopping) {
      final speed = math.max(speedMps, 2.5);
      final ms = ((remainingMeters / speed) * 1000).round();
      return ms.clamp(minDurationMs, maxStopDurationMs);
    }

    if (remainingMeters > largeJumpMeters) {
      final speed = math.max(speedMps, 8.0);
      final ms = ((remainingMeters / speed) * 1000).round();
      return ms.clamp(160, maxJumpDurationMs);
    }

    final speed = speedMps < minSpeedForDuration
        ? minSpeedForDuration
        : speedMps.clamp(minSpeedForDuration, 55.0);
    final expectedHop = math.max(speed * (interval / 1000.0), 0.5);
    final behindRatio = remainingMeters / expectedHop;

    if (behindRatio <= 1.35) {
      return interval.clamp(minDurationMs, maxOnTrackDurationMs);
    }

    final catchUp = (interval * (1.0 + 0.2 * (behindRatio - 1.0))).round();
    return catchUp.clamp(minDurationMs, maxDurationMs);
  }

  static double lerpHeading(double from, double to, double t) {
    final delta = shortestAngleDelta(from, to);
    return (from + delta * t.clamp(0.0, 1.0) + 360) % 360;
  }

  /// Prefer GPS/socket course when the vehicle is actually moving. Android
  /// reports `0` both for "north" and "heading unavailable" — if a movement
  /// bearing exists and disagrees with 0 by more than 45°, use movement.
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

  static double _easeOutCubic(double t) {
    final inv = 1 - t;
    return 1 - inv * inv * inv;
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
