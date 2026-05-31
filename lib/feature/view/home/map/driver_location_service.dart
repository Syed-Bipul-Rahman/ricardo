import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ricardo/services/socket_services.dart';

class DriverLocationService with WidgetsBindingObserver {
  // Singleton
  static final DriverLocationService _instance =
  DriverLocationService._internal();

  factory DriverLocationService() => _instance;

  DriverLocationService._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  StreamSubscription<Position>? _positionSubscription;

  String? _rideId;

  bool get isRunning => _positionSubscription != null;

  /// Start listening location changes
  void startEmitting(String rideId) {
    stop();

    _rideId = rideId;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,

        // Emit only when driver moves 20 meters
        distanceFilter: 20,
      ),
    ).listen(
          (Position position) {
        if (SocketServices.socket?.connected != true) {
          debugPrint('❌ Socket disconnected');
          return;
        }

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

  /// Stop service
  void stop() {
    _positionSubscription?.cancel();
    _positionSubscription = null;

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