import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ricardo/services/socket_services.dart';

class DriverLocationService with WidgetsBindingObserver {
  static final DriverLocationService _instance =
      DriverLocationService._internal();

  factory DriverLocationService() => _instance;

  DriverLocationService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  StreamSubscription<Position>? _positionSubscription;
  Position? _lastEmittedPosition;
  DateTime? _lastEmittedAt;

  String? _rideId;

  bool get isRunning => _positionSubscription != null;

  /// Start listening location changes
  void startEmitting(String rideId) {
    stop();

    _rideId = rideId;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        if (SocketServices.socket?.connected != true) {
          debugPrint('❌ Socket disconnected');
          return;
        }

        if (!_shouldEmit(position)) return;
        _lastEmittedPosition = position;
        _lastEmittedAt = DateTime.now();

        SocketServices.socket?.emit(
          'get-driver-location',
          {
            'rideId': rideId,
          },
        );

        debugPrint(
          '📡 Driver moved → emitted location '
          '(${position.latitude}, ${position.longitude})',
        );
      },
      onError: (e) {
        debugPrint('❌ Location stream error: $e');
      },
    );

    debugPrint('✅ Started location stream for rideId: $rideId');
  }

  bool _shouldEmit(Position position) {
    if (position.accuracy > 75) return false;

    final previous = _lastEmittedPosition;
    final emittedAt = _lastEmittedAt;
    if (previous == null || emittedAt == null) return true;
    if (DateTime.now().difference(emittedAt) < const Duration(seconds: 2)) {
      return false;
    }

    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );
    final minimumMovement =
        position.speed >= 0 && position.speed < 0.5 ? 8.0 : 5.0;
    if (distance < minimumMovement) return false;
    if (position.accuracy > 35 && distance < 12) return false;
    return true;
  }

  /// Stop service
  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _lastEmittedPosition = null;
    _lastEmittedAt = null;

    debugPrint('🛑 Stopped location stream for rideId: $_rideId');

    _rideId = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        stop();
        debugPrint('💀 App terminated');
        break;

      case AppLifecycleState.resumed:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        debugPrint('📱 Lifecycle: $state');
        break;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stop();
  }
}
