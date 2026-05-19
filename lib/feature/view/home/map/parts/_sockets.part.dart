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
    });

    SocketServices.socket?.on('ride-accepted-driver', (data) {
      if (data is Map<String, dynamic>) {
        if (data['isRideAcceptedDriver'] == true) {
          mapOPTController.acceptedRideDriverDataStatus.value = true;
          mapOPTController.acceptedRideDriverData.value =
              AcceptRideDriverModel.fromJson(data);
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

        // On the passenger side, use the driver's real-time location from the
        // socket to update the polyline instead of the passenger's own GPS.
        final bool isPassenger =
            userController.userModel.value?.userProfile?.role ==
                AppConstants.passenger;
        if (isPassenger) {
          final coords = mapOPTController
              .getRideDriverLocation.value?.driverLocation?.coordinates;
          if (coords != null && coords.length >= 2) {
            final driverLatLng = LatLng(coords[1], coords[0]);
            if (_fullRoutePoints.isEmpty) {
              // No route drawn yet — draw it now that we have driver location.
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

        mapOPTController.rideStatusData.value = rideStatus;

        if (rideStatus.acceptRide == true) {
          rideController.drivers.clear();
          mapOPTController.isCurrentMarkerShowOrNot.value = true;
        } else if (rideStatus.ongoingRide == true) {
          loadAcceptedRideRoute();
        } else if (rideStatus.arrivingRide == true) {
          markers.clear();
          _polylines.clear();
        } else if (rideStatus.startRide == true) {
          pickupToDestinationRoute();
        } else if (rideStatus.driverCancel == true ||
            rideStatus.passengerCancel == true) {
          debugPrint('❌ ride-status: Ride cancelled');
          clearRideState();
          SocketServices.socket?.off('ride-status');
        }

        await mapOPTController.driverServiceFun();
      } catch (e, stackTrace) {
        debugPrint('ride-status ERROR: $e');
        debugPrint('STACK: $stackTrace');
      }
    });
  }

  void disconnectSocket() {
    SocketServices.socket?.off('new-ride-request');
    SocketServices.socket?.off('cancel-ride-request');
    SocketServices.socket?.off('ride-accepted');
    SocketServices.socket?.off('ride-accepted-driver');
    SocketServices.socket?.off('get-ride-driver-location');
    SocketServices.socket?.off('ride-status');
  }
}
