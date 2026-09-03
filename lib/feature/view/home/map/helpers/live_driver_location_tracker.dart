import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Validated, ordered remote-driver location samples for the passenger map.
///
/// Keeps the latest authoritative position and rejects stale / invalid /
/// duplicate events so marker animation never moves backward from old data.
class LiveDriverLocationTracker {
  static const double maxAcceptedAccuracyMeters = 75;
  static const double stoppedSpeedMps = 0.5;
  static const double duplicateDistanceMeters = 0.8;
  static const Duration maxSampleAge = Duration(seconds: 30);

  LatLng? lastAccepted;
  DateTime? lastAcceptedAt;
  DateTime? lastGpsTimestamp;
  double lastSpeedMps = 0;
  double lastHeading = 0;
  double lastAccuracyMeters = 0;
  int acceptedSequence = 0;

  /// Interval between the last two *accepted* samples (for animation timing).
  Duration? lastUpdateInterval;

  void reset() {
    lastAccepted = null;
    lastAcceptedAt = null;
    lastGpsTimestamp = null;
    lastSpeedMps = 0;
    lastHeading = 0;
    lastAccuracyMeters = 0;
    acceptedSequence = 0;
    lastUpdateInterval = null;
  }

  /// Returns null when the sample must be ignored.
  LiveDriverLocationSample? accept({
    required double latitude,
    required double longitude,
    DateTime? gpsTimestamp,
    double? speedMps,
    double? headingDegrees,
    double? accuracyMeters,
    DateTime? receivedAt,
  }) {
    final now = receivedAt ?? DateTime.now();

    if (!_isValidCoordinate(latitude, longitude)) {
      return null;
    }

    if (accuracyMeters != null &&
        accuracyMeters.isFinite &&
        accuracyMeters > maxAcceptedAccuracyMeters) {
      return null;
    }

    if (gpsTimestamp != null) {
      if (lastGpsTimestamp != null &&
          !gpsTimestamp.isAfter(lastGpsTimestamp!)) {
        return null;
      }
      if (now.difference(gpsTimestamp) > maxSampleAge) {
        return null;
      }
    }

    final target = LatLng(latitude, longitude);
    final previous = lastAccepted;
    final previousAt = lastAcceptedAt;

    if (previous != null && previousAt != null) {
      final distance = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        target.latitude,
        target.longitude,
      );

      // Exact / near-duplicate of the last accepted socket sample.
      if (distance < duplicateDistanceMeters) {
        final resolvedSpeed = _resolveSpeed(
          reported: speedMps,
          distanceMeters: distance,
          interval: now.difference(previousAt),
          previousSpeed: lastSpeedMps,
          preferStopped: true,
        );
        lastAcceptedAt = now;
        lastSpeedMps = resolvedSpeed;
        if (accuracyMeters != null && accuracyMeters.isFinite) {
          lastAccuracyMeters = accuracyMeters;
        }
        if (gpsTimestamp != null) lastGpsTimestamp = gpsTimestamp;
        return LiveDriverLocationSample(
          position: previous,
          previousPosition: previous,
          receivedAt: now,
          gpsTimestamp: gpsTimestamp ?? lastGpsTimestamp,
          speedMps: resolvedSpeed,
          headingDegrees: lastHeading,
          accuracyMeters: lastAccuracyMeters,
          distanceFromPreviousMeters: distance,
          intervalFromPrevious: now.difference(previousAt),
          sequence: acceptedSequence,
          isDuplicate: true,
          isStopped: resolvedSpeed < stoppedSpeedMps,
        );
      }

      // Reject physically impossible jumps (e.g. delayed/stale burst).
      final elapsedSec =
          now.difference(previousAt).inMilliseconds.clamp(1, 60000) / 1000.0;
      final impliedSpeed = distance / elapsedSec;
      if (impliedSpeed > 70 && distance > 120) {
        return null;
      }
    }

    final interval = previousAt == null ? null : now.difference(previousAt);
    if (interval != null) {
      lastUpdateInterval = interval;
    }

    final distance = previous == null
        ? 0.0
        : Geolocator.distanceBetween(
            previous.latitude,
            previous.longitude,
            target.latitude,
            target.longitude,
          );

    final resolvedSpeed = _resolveSpeed(
      reported: speedMps,
      distanceMeters: distance,
      interval: interval ?? const Duration(seconds: 1),
      previousSpeed: lastSpeedMps,
      preferStopped: false,
    );

    final heading = headingDegrees != null && headingDegrees.isFinite
        ? (headingDegrees % 360 + 360) % 360
        : (previous != null && distance >= 0.5
            ? _bearingBetween(previous, target)
            : lastHeading);

    lastAccepted = target;
    lastAcceptedAt = now;
    if (gpsTimestamp != null) lastGpsTimestamp = gpsTimestamp;
    lastSpeedMps = resolvedSpeed;
    lastHeading = heading;
    if (accuracyMeters != null && accuracyMeters.isFinite) {
      lastAccuracyMeters = accuracyMeters;
    }
    acceptedSequence += 1;

    return LiveDriverLocationSample(
      position: target,
      previousPosition: previous,
      receivedAt: now,
      gpsTimestamp: gpsTimestamp ?? lastGpsTimestamp,
      speedMps: resolvedSpeed,
      headingDegrees: heading,
      accuracyMeters: lastAccuracyMeters,
      distanceFromPreviousMeters: distance,
      intervalFromPrevious: interval,
      sequence: acceptedSequence,
      isDuplicate: false,
      isStopped: resolvedSpeed < stoppedSpeedMps,
    );
  }

  double _resolveSpeed({
    required double? reported,
    required double distanceMeters,
    required Duration interval,
    required double previousSpeed,
    required bool preferStopped,
  }) {
    if (reported != null && reported.isFinite && reported >= 0) {
      if (reported < stoppedSpeedMps) return 0;
      return reported.clamp(0.0, 55.0).toDouble();
    }

    final seconds = interval.inMilliseconds / 1000.0;
    if (seconds <= 0) return preferStopped ? 0 : previousSpeed;

    if (distanceMeters < duplicateDistanceMeters) {
      return 0;
    }

    final measured = distanceMeters / seconds;
    if (measured < stoppedSpeedMps) return 0;

    if (previousSpeed > stoppedSpeedMps && !preferStopped) {
      return (previousSpeed * 0.55 + measured * 0.45).clamp(0.0, 55.0);
    }
    return measured.clamp(0.0, 55.0);
  }

  static bool _isValidCoordinate(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat == 0 && lng == 0) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  static double _bearingBetween(LatLng from, LatLng to) {
    final fromLat = from.latitude * math.pi / 180;
    final toLat = to.latitude * math.pi / 180;
    final lngDelta = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(lngDelta) * math.cos(toLat);
    final x = math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(lngDelta);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

class LiveDriverLocationSample {
  final LatLng position;
  final LatLng? previousPosition;
  final DateTime receivedAt;
  final DateTime? gpsTimestamp;
  final double speedMps;
  final double headingDegrees;
  final double accuracyMeters;
  final double distanceFromPreviousMeters;
  final Duration? intervalFromPrevious;
  final int sequence;
  final bool isDuplicate;
  final bool isStopped;

  const LiveDriverLocationSample({
    required this.position,
    required this.previousPosition,
    required this.receivedAt,
    required this.gpsTimestamp,
    required this.speedMps,
    required this.headingDegrees,
    required this.accuracyMeters,
    required this.distanceFromPreviousMeters,
    required this.intervalFromPrevious,
    required this.sequence,
    required this.isDuplicate,
    required this.isStopped,
  });
}
