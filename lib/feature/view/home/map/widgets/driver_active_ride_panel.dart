import 'package:flutter/material.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/feature/view/home/map/dialogs/cancel_reason_sheet.dart';
import 'package:ricardo/widgets/custom_loader.dart';

class DriverActiveRidePanel extends StatelessWidget {
  const DriverActiveRidePanel({
    super.key,
    required this.mapOPTController,
    required this.onRideCancelled,
  });

  final MapOPTController mapOPTController;
  final VoidCallback onRideCancelled;

  @override
  Widget build(BuildContext context) {
    return GlassBackgroundWidget(
      child: Obx(() {
        final rideStatus = mapOPTController.rideStatusData.value;

        final bool isOnTheWay =
            rideStatus == null || rideStatus.acceptRide == true;

        final bool isStartRide = rideStatus?.startRide == true;

        final bool isArriving = rideStatus?.arrivingRide == true;

        final bool isOngoing = rideStatus?.ongoingRide == true;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Obx(() {
                  final rideData =
                      mapOPTController.getRideDriverLocation.value;

                  final distance =
                      rideData?.driverToPickup?.distance?.value ?? 0;
                  final int time =
                      rideData?.driverToPickup?.time?.value ?? 0;
                  String convertSecondsToTime(int seconds) {
                    if (seconds < 0) return '0 Min';

                    final int days = seconds ~/ 86400;
                    final int hours = (seconds % 86400) ~/ 3600;
                    final int minutes = (seconds % 3600) ~/ 60;
                    final int secs = seconds % 60;

                    if (days > 0) {
                      if (hours > 0)
                        return '$days Day${days > 1 ? 's' : ''} $hours Hr${hours > 1 ? 's' : ''}';
                      return '$days Day${days > 1 ? 's' : ''}';
                    }

                    if (hours > 0) {
                      if (minutes > 0)
                        return '$hours Hr${hours > 1 ? 's' : ''} $minutes Min';
                      return '$hours Hr${hours > 1 ? 's' : ''}';
                    }

                    if (minutes > 0) {
                      if (secs > 0) return '$minutes Min $secs Sec';
                      return '$minutes Min';
                    }

                    return '$secs Sec';
                  }

                  String convertMetersToDistance(double meters) {
                    if (meters < 0) return '0 M';

                    if (meters < 1000) {
                      return '${meters.toStringAsFixed(0)} M';
                    }

                    final double km = meters / 1000;

                    if (km < 100) {
                      return '${km.toStringAsFixed(2)} KM';
                    }

                    return '${km.toStringAsFixed(1)} KM';
                  }

                  return Text(
                    '( ${convertSecondsToTime(time)}) ${convertMetersToDistance(distance.toDouble())}',
                    style: TextStyle(
                      color: AppColors.timeAndDurationColor,
                      fontWeight: FontWeight.bold,
                      fontFamily: FontFamily.poppins,
                      fontSize: 20.sp,
                    ),
                  );
                }),
                const SizedBox(width: 10),
                Visibility(
                  visible: rideStatus?.acceptRide == true ||
                      rideStatus?.ongoingRide == true ||
                      rideStatus?.arrivingRide == true,
                  child: GestureDetector(
                    onTap: () {
                      mapOPTController.showCancelReasonDialog.value = true;
                      showCancelReasonSheet(
                        context,
                        mapOPTController: mapOPTController,
                        onConfirmed: onRideCancelled,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.red, width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block, color: Colors.red, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Cancel',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 28),
            Divider(height: 1, color: Colors.black.withOpacity(0.2)),
            const SizedBox(height: 16),
            Obx(() {
              final rideStatus = mapOPTController.rideStatusData.value;

              if (rideStatus == null) {
                return const SizedBox(
                  height: 70,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final filename =
                  rideStatus.ride?.passenger?.image?.filename;
              final hasImage = filename != null && filename.isNotEmpty;
              final imageUrl =
                  hasImage ? '${ApiUrls.imageBaseUrl}$filename' : null;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                height: 50,
                                width: 50,
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (context, error, stackTrace) {
                                  return Image.asset(
                                    'assets/images/default_image.jpg',
                                    height: 50,
                                    width: 50,
                                    fit: BoxFit.cover,
                                  );
                                },
                              )
                            : Image.asset(
                                'assets/images/default_image.jpg',
                                height: 50,
                                width: 50,
                                fit: BoxFit.cover,
                              ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rideStatus.ride?.passenger?.name ??
                                'Unknown Passenger',
                            style: TextStyle(
                              color: const Color(0xff171717),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              fontFamily: FontFamily.poppins,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '\$${rideStatus.ride?.fare ?? 0.0} ',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '(${((rideStatus.ride?.destinationMeters ?? 0) / 1000).toStringAsFixed(2)} KM)',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      launchUrl(
                        Uri.parse("tel:${rideStatus.passenger?.phone}"),
                      );
                    },
                    child: RepaintBoundary(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.whiteColor,
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: AppColors.greyColor200),
                        ),
                        child: SvgPicture.asset(
                            Assets.icons.driverCardPhone),
                      ),
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 24),
            Obx(() {
              final locationData =
                  mapOPTController.getRideDriverLocation.value;
              final rideStatus = mapOPTController.rideStatusData.value;

              final bool enableArriveInPlace =
                  (rideStatus?.ongoingRide == true) &&
                      (locationData?.driverToPickup?.distance?.value ??
                              double.maxFinite.toInt()) <=
                          200;

              final bool enableComplete = (rideStatus?.startRide == true) &&
                  (locationData?.driverToDestination?.distance?.value ??
                          double.maxFinite.toInt()) <=
                      200;

              debugPrint(
                  '================>>>>>>>>>>> Location Data ${locationData?.driverToDestination?.distance} ${locationData?.driverToPickup?.distance} ');

              String getButtonTitle() {
                if (rideStatus == null) return 'Loading...';
                if (rideStatus.acceptRide == true) return 'On the way';
                if (rideStatus.ongoingRide == true) return 'Arrive in Place';
                if (rideStatus.arrivingRide == true) return 'Start Ride';
                if (rideStatus.startRide == true) return 'Complete';
                return 'Loading...';
              }

              bool isButtonEnabled() {
                if (rideStatus == null) return false;
                if (rideStatus.acceptRide == true) return true;
                if (rideStatus.ongoingRide == true)
                  return enableArriveInPlace;
                if (rideStatus.arrivingRide == true) return true;
                if (rideStatus.startRide == true) return enableComplete;
                return false;
              }

              return mapOPTController.isRideStatusChangeLoading.value ==
                          true ||
                      mapOPTController.isCompleteRideLoading.value == true
                  ? CustomLoader()
                  : CustomPrimaryButton(
                      title: getButtonTitle(),
                      onHandler: isButtonEnabled()
                          ? () async {
                              final rideId = rideStatus?.ride?.id;
                              if (rideId == null) return;

                              if (rideStatus?.acceptRide == true) {
                                debugPrint('🚕 accepted → ongoing');
                                mapOPTController.rideStatusChange(
                                    rideId, 'ongoing');
                              } else if (rideStatus?.ongoingRide == true) {
                                debugPrint('🚕 ongoing → arriving');
                                mapOPTController.rideStatusChange(
                                    rideId, 'arriving');
                              } else if (rideStatus?.arrivingRide == true) {
                                debugPrint('🚕 arriving → start_ride');
                                mapOPTController.rideStatusChange(
                                    rideId, 'start_ride');
                              } else if (rideStatus?.startRide == true) {
                                debugPrint('🚕 start_ride → complete');
                                mapOPTController.isPassengerRequest.value =
                                    false;
                                mapOPTController.completeRideHandler(
                                    rideId, 0);
                              }
                            }
                          : null,
                    );
            }),
            const SizedBox(height: 80),
          ],
        );
      }),
    );
  }
}
