part of '../../map_screen.dart';

extension _Sockets on _MapScreenState {
  Future<void> connectSocket() async {
    String? fcmToken = await FirebaseNotificationService.getFCMToken();
    await PrefsHelper.setString(AppConstants.fcmToken, fcmToken);

    SocketServices.socket?.on('new-ride-request', (data) {
      if (data['newRideRequest'] == true) {
        mapOPTController.startRideRequestTimer();
        mapOPTController.isPassengerRequest.value = true;
        mapOPTController.rideDetailsData.value =
            RideDetailsSocketModel.fromJson(data['rideDetails']);
      }
    });

    SocketServices.socket?.on('cancel-ride-request', (data) {
      if (data['isCancelPickRequest'] == true) {
        mapOPTController.isPassengerRequest.value = false;
        mapOPTController.cancelRideRequestTimer();
      }
    });

    SocketServices.socket?.on('ride-accepted', (data) {
      if (data is! Map<String, dynamic>) return;
      if (data['isRideAccepted'] != true) return;

      final driver = data['driver'];
      rideController.isRideAccepted.value = true;
      rideController.acceptedRideDriverName.value =
          (driver is Map ? driver['driverName'] : null) ?? '';

      try {
        rideController.acceptRideModel.value = AcceptRideModel.fromJson(data);
      } catch (e) {
        debugPrint('ride-accepted parse error: $e');
      }

      final rideId = rideController.acceptRideModel.value?.ride?.id;
      if (rideId != null && rideId.isNotEmpty) {
        mapOPTController.startRideLocationSync(rideId);
      }
    });

    SocketServices.socket?.on('ride-accepted-driver', (data) {
      if (data is Map<String, dynamic>) {
        if (data['isRideAcceptedDriver'] == true) {
          mapOPTController.acceptedRideDriverDataStatus.value = true;
          mapOPTController.acceptedRideDriverData.value =
              AcceptRideDriverModel.fromJson(data);
          mapOPTController.isPassengerRequest.value = false;
          mapOPTController.cancelRideRequestTimer();

          final rideId =
              mapOPTController.acceptedRideDriverData.value?.ride?.sId;
          if (rideId != null && rideId.isNotEmpty) {
            mapOPTController.startRideLocationSync(rideId);
            mapOPTController.prefetchPickupRouteEstimate();
          }
        }
      }
    });

    SocketServices.socket?.off('get-ride-driver-location');
    SocketServices.socket?.on('get-ride-driver-location', (data) {
      try {
        Map<String, dynamic> jsonData;
        if (data is List) {
          jsonData = Map<String, dynamic>.from(data[0]);
        } else if (data is String) {
          jsonData = jsonDecode(data);
        } else if (data is Map) {
          jsonData = Map<String, dynamic>.from(data);
        } else {
          return;
        }
        mapOPTController.getRideDriverLocation.value =
            GetRideDriverLocation.fromJson(jsonData);
        mapOPTController.getRideDriverLocation.refresh();
        mapOPTController.markDriverLocationSocketReceived();
        final bool isPassenger =
            userController.userModel.value?.userProfile?.role ==
                AppConstants.passenger;
        if (isPassenger) {
          final coords = mapOPTController
              .getRideDriverLocation.value?.driverLocation?.coordinates;
          if (coords != null && coords.length >= 2) {
            final driverLatLng = LatLng(coords[1], coords[0]);
            if (_fullRoutePoints.isEmpty) {
              final rideStatus = mapOPTController.rideStatusData.value;
              if (rideStatus?.startRide == true ||
                  rideStatus?.completeRide == true) {
                pickupToDestinationRoute();
              } else {
                loadAcceptedRideRoute();
              }
            } else {
              updatePolylineForDriverPosition(driverLatLng);
            }
          }
        }

        debugPrint('📍 Driver location updated');
      } catch (e) {
        debugPrint('get-ride-driver-location error: $e');
      }
    });

    SocketServices.socket?.on('ride-status', (data) async {
      try {
        Map<String, dynamic> jsonData;
        if (data is List) {
          jsonData = Map<String, dynamic>.from(data[0]);
        } else if (data is String) {
          jsonData = jsonDecode(data);
        } else if (data is Map) {
          jsonData = Map<String, dynamic>.from(data);
        } else {
          return;
        }

        final RideModel.RideStatusModel rideStatus =
            RideModel.RideStatusModel.fromJson(jsonData);

        final rideId = rideStatus.ride?.id;
        if (mapOPTController.shouldIgnoreRideStatus(rideId) &&
            rideStatus.completeRide != true &&
            rideStatus.driverCancel != true &&
            rideStatus.passengerCancel != true) {
          debugPrint('ride-status ignored — ride already finished locally');
          return;
        }

        if (rideStatus.completeRide == true) {
          debugPrint('✅ ride-status: Ride completed');
          await finishRide(rideId: rideId);
          return;
        }

        if (rideStatus.driverCancel == true ||
            rideStatus.passengerCancel == true) {
          debugPrint('❌ ride-status: Ride cancelled');
          await finishRide(rideId: rideId);
          SocketServices.socket?.off('ride-status');
          return;
        }

        mapOPTController.rideStatusData.value = rideStatus;
        mapOPTController.rideStatusData.refresh();

        if (rideStatus.acceptRide == true) {
          rideController.drivers.clear();
          mapOPTController.isCurrentMarkerShowOrNot.value = true;
          mapOPTController.isPassengerRequest.value = false;
          mapOPTController.cancelRideRequestTimer();

          final isDriver =
              userController.userModel.value?.userProfile?.role ==
                  AppConstants.driver;
          final rideId = rideStatus.ride?.id;
          if (rideId != null && rideId.isNotEmpty) {
            mapOPTController.startRideLocationSync(rideId);
            if (isDriver) {
              mapOPTController.prefetchPickupRouteEstimate();
            }
          }
        } else if (rideStatus.ongoingRide == true) {
          final rideId = rideStatus.ride?.id;
          if (rideId != null && rideId.isNotEmpty) {
            mapOPTController.maybeEmitGetDriverLocation(rideId);
          }
          loadAcceptedRideRoute();
        } else if (rideStatus.arrivingRide == true) {
          markers.clear();
          _polylines.clear();
          _fullRoutePoints = [];
          _routeTarget = null;
        } else if (rideStatus.startRide == true) {
          _fullRoutePoints = [];
          _routeTarget = null;
          mapOPTController.prefetchDestinationRouteEstimate();
          final rideId = rideStatus.ride?.id;
          if (rideId != null && rideId.isNotEmpty) {
            mapOPTController.maybeEmitGetDriverLocation(rideId);
          }
          pickupToDestinationRoute();
        }

      } catch (e, stackTrace) {
        debugPrint('ride-status ERROR: $e');
        debugPrint('STACK: $stackTrace');
      }
    });

    SocketServices.onReconnected =
        mapOPTController.resumeRideLocationSyncIfNeeded;
  }

  void disconnectSocket() {
    SocketServices.onReconnected = null;
    SocketServices.socket?.off('new-ride-request');
    SocketServices.socket?.off('cancel-ride-request');
    SocketServices.socket?.off('ride-accepted');
    SocketServices.socket?.off('ride-accepted-driver');
    SocketServices.socket?.off('get-ride-driver-location');
    SocketServices.socket?.off('ride-status');
  }
}
