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
/// One 50 ms timer. New samples never cancel-restart from raw GPS; they
/// replace the remaining polyline from the current displayed position.
class VehicleMotionEngine {
  VehicleMotionEngine({this.smoothObservedSpeed = true});

  static const int frameMs = 50;
  static const double speedAlpha = 0.35;
  static const double startAlpha = 0.55;
  static const double stoppedSpeedMps = 0.5;
  static const int minDurationMs = 80;
  static const int maxDurationMs = 4000;
  static const int maxStopDurationMs = 1200;
  static const double minSpeedForDuration = 0.3;
  static const double arrivalProximityMeters = 12;
  static const double settleDistanceMeters = 0.5;

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

  List<LatLng> _path = const [];
  DateTime? _pathStartedAt;
  int _durationMs = 0;
  bool _easeOut = false;
  LatLng? _pendingTarget;
  List<LatLng>? _pendingPath;
  bool _pendingStop = false;
  bool _offRoute = false;
  Timer? _timer;

  void observe({
    required LatLng target,
    required List<LatLng> path,
    required double observedSpeedMps,
    required bool isStopped,
    bool offRoute = false,
    double? remainingToDestinationMeters,
  }) {
    if (phase == VehicleMotionPhase.arrived) return;

    _offRoute = offRoute;
    _applySpeed(observedSpeedMps, forceZero: isStopped);

    if (remainingToDestinationMeters != null &&
        remainingToDestinationMeters < arrivalProximityMeters &&
        (isStopped || smoothedSpeedMps < stoppedSpeedMps)) {
      _settle(
        path.length >= 2 ? path.last : (displayedPosition ?? target),
        VehicleMotionPhase.stopped,
      );
      return;
    }

    final from = displayedPosition;
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

    if (_timer?.isActive == true) return;
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
    _path = const [];
    _pathStartedAt = null;
    _durationMs = 0;
    _easeOut = false;
    _offRoute = false;
    smoothedSpeedMps = 0;
    phase = to;
  }

  void reset() {
    halt(to: VehicleMotionPhase.idle);
    displayedPosition = null;
    displayedHeading = 0;
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
      smoothedSpeedMps =
          speedAlpha * raw + (1 - speedAlpha) * smoothedSpeedMps;
    }
    if (smoothedSpeedMps < stoppedSpeedMps) smoothedSpeedMps = 0;
  }

  void _applyPendingIfAny() {
    final pendingPath = _pendingPath;
    final pendingTarget = _pendingTarget;
    if (pendingPath == null || pendingTarget == null) return;
    _pendingPath = null;
    _pendingTarget = null;
    final stopping = _pendingStop;
    _pendingStop = false;

    final from = displayedPosition ?? pendingPath.first;
    var path = List<LatLng>.from(pendingPath);
    if (path.isEmpty) {
      path = [from, pendingTarget];
    } else if (!_pointsEqual(path.first, from) &&
        _distance(from, path.first) > 2) {
      path.insert(0, from);
    }

    if (path.length < 2) {
      _settle(path.isEmpty ? pendingTarget : path.last,
          stopping ? VehicleMotionPhase.stopped : phase);
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

    if (displayedPosition == null && path.length >= 2) {
      displayedHeading =
          alongPath?.call(path, 0).bearing ?? displayedHeading;
    }
    displayedPosition ??= path.first;
    _path = path;
    _easeOut = stopping;
    phase = stopping
        ? VehicleMotionPhase.stopping
        : VehicleMotionPhase.moving;
    _durationMs = durationMsFor(
      remainingMeters: remaining,
      speedMps: stopping
          ? math.max(smoothedSpeedMps, minSpeedForDuration)
          : smoothedSpeedMps,
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
        final hold = displayedPosition ??
            (_path.isNotEmpty ? _path.last : null);
        if (phase == VehicleMotionPhase.stopping && hold != null) {
          _settle(hold, VehicleMotionPhase.stopped);
          return;
        }
        timer.cancel();
        _timer = null;
        return;
      }

      final elapsed =
          DateTime.now().difference(_pathStartedAt!).inMilliseconds;
      var t = (elapsed / _durationMs).clamp(0.0, 1.0);
      if (_easeOut) t = _easeOutCubic(t);

      final along = alongPath?.call(_path, t) ?? _fallbackAlong(_path, t);
      final lookAheadM =
          _offRoute ? 0.0 : lookAheadMeters(smoothedSpeedMps);
      final desired = lookAheadBearing?.call(_path, t, lookAheadM) ??
          along.bearing;
      final turnDelta = shortestAngleDelta(displayedHeading, desired).abs();
      final maxStep = turnDelta > 12 ? 8.0 : 16.0;
      displayedHeading = stepHeading(displayedHeading, desired, maxStep);
      displayedPosition = along.position;

      onFrame?.call(displayedPosition!, displayedHeading);

      if (elapsed >= _durationMs) {
        displayedPosition = _path.last;
        onFrame?.call(displayedPosition!, displayedHeading);
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
    _timer?.cancel();
    _timer = null;
    onFrame?.call(at, displayedHeading);
    onSettled?.call();
  }

  static int durationMsFor({
    required double remainingMeters,
    required double speedMps,
    bool stopping = false,
  }) {
    if (remainingMeters < settleDistanceMeters) return 0;
    final speed = speedMps < minSpeedForDuration
        ? minSpeedForDuration
        : speedMps.clamp(minSpeedForDuration, 55.0);
    final ms = ((remainingMeters / speed) * 1000).round();
    if (stopping) {
      return ms.clamp(minDurationMs, maxStopDurationMs);
    }
    return ms.clamp(minDurationMs, maxDurationMs);
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
            path[i].longitude +
                (path[i + 1].longitude - path[i].longitude) * t,
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
