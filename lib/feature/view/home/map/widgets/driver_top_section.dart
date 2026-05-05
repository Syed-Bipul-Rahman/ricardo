import 'package:flutter/material.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';

class DriverTopSection extends StatelessWidget {
  const DriverTopSection({
    super.key,
    required this.userController,
    required this.rideController,
    required this.mapOPTController,
  });

  final UserController userController;
  final RideController rideController;
  final MapOPTController mapOPTController;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Obx(() {
          if (mapOPTController.acceptedRideDriverData.value
                  ?.isRideAcceptedDriver ==
              true) {
            return SizedBox(height: 20.h);
          }
          return const SizedBox.shrink();
        }),
        const SizedBox(height: 20),
        Obx(() {
          final role = userController.userModel.value?.userProfile?.role;
          final isDriver = role == AppConstants.driver;
          final isAcceptedDriver = mapOPTController
                  .acceptedRideDriverData.value?.isRideAcceptedDriver ??
              false;
          final status = mapOPTController.rideStatusData.value;

          if (isDriver &&
              !mapOPTController.acceptedRideDriverDataStatus.value &&
              !isAcceptedDriver &&
              rideController.isRideAccepted.value == false &&
              (status?.acceptRide ?? false) == false &&
              (status?.ongoingRide ?? false) == false &&
              (status?.startRide ?? false) == false &&
              (status?.arrivingRide ?? false) == false &&
              (status?.driverCancel ?? false) == false &&
              (status?.passengerCancel ?? false) == false &&
              (status?.completeRide ?? false) == false) {
            return AnimatedToggleSwitch();
          }
          return const SizedBox.shrink();
        }),
        Obx(() {
          final role = userController.userModel.value?.userProfile?.role;
          final status = mapOPTController.rideStatusData.value;
          final isAcceptedDriver = mapOPTController
                  .acceptedRideDriverData.value?.isRideAcceptedDriver ??
              false;

          final shouldShow = role == AppConstants.driver &&
              (isAcceptedDriver ||
                  mapOPTController.acceptedRideDriverDataStatus.value == true ||
                  status?.acceptRide == true ||
                  status?.ongoingRide == true ||
                  status?.arrivingRide == true ||
                  status?.driverCancel == true ||
                  status?.passengerCancel == true ||
                  status?.startRide == true ||
                  status?.completeRide == true);

          if (!shouldShow) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: SizedBox(
              width: double.infinity,
              child: GlassBackgroundWidget(
                borderLeftRightRadius: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    const Icon(Icons.location_pin, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<Map<String, String>>(
                            future:
                                DirectionsService().getCurrentAddressParts(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Text('Loading...');
                              }
                              if (snapshot.hasError || !snapshot.hasData) {
                                return const Text('Error getting address');
                              }
                              return Text(
                                snapshot.data!['firstLine'] ??
                                    'No address found',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: FontFamily.poppins,
                                  color: const Color(0xff171717),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              );
                            },
                          ),
                          FutureBuilder<Map<String, String>>(
                            future:
                                DirectionsService().getCurrentAddressParts(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Text('Loading...');
                              }
                              if (snapshot.hasError || !snapshot.hasData) {
                                return const Text('Error getting address');
                              }
                              return Text(
                                snapshot.data!['secondLine'] ??
                                    'No address found',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: FontFamily.poppins,
                                  color: const Color(0xffA3A3A3),
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        Obx(() {
          final offlineOnline =
              userController.userModel.value?.userProfile?.role ==
                      AppConstants.driver &&
                  mapOPTController.userController.userModel.value
                          ?.driverProfile?.isOnline ==
                      false &&
                  mapOPTController.rideStatusData.value?.acceptRide != true &&
                  mapOPTController.rideStatusData.value?.ongoingRide != true &&
                  mapOPTController.rideStatusData.value?.arrivingRide !=
                      true &&
                  mapOPTController.rideStatusData.value?.driverCancel !=
                      true &&
                  mapOPTController.rideStatusData.value?.passengerCancel !=
                      true &&
                  mapOPTController.rideStatusData.value?.startRide != true &&
                  mapOPTController.rideStatusData.value?.completeRide != true;

          if (offlineOnline) return const NoInternetMessageMap();
          return const SizedBox.shrink();
        }),
      ],
    );
  }
}
