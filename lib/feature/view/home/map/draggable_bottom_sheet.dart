import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ricardo/app/helpers/ride_distance_formatter.dart';
import 'package:ricardo/app/helpers/ride_eta_resolver.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/widgets/widgets.dart';

class DraggableBottomSheet extends StatefulWidget {
  final RideStatusModel? rideStatus;
  final MapOPTController? controller;

  const DraggableBottomSheet({
    super.key,
    this.rideStatus,
    this.controller,
  });

  @override
  State<DraggableBottomSheet> createState() => _DraggableBottomSheetState();
}

class _DraggableBottomSheetState extends State<DraggableBottomSheet> {
  final controller = Get.find<MapOPTController>();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final data = controller.rideStatusData.value;

      final isComplete = data?.completeRide == true;
      final isArriving = data?.arrivingRide == true;

      debugPrint(
        '🧳📋 bottom sheet build | completeRide=${data?.completeRide} '
        'startRide=${data?.startRide} isComplete=$isComplete rideId=${data?.ride?.id}',
      );

      return DraggableScrollableSheet(
        initialChildSize: 0.35,
        minChildSize: 0.10,
        maxChildSize: (isComplete || isArriving) ? 0.45 : 0.5,
        expand: false,
        builder: (context, scrollController) {
          return GlassBackgroundWidget(
            blurNumber: 16,
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // ───────────────── HEADER ─────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 18,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),

                        /// drag handle
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),

                        const SizedBox(height: 12),

                        /// STATUS TEXT (FULLY REACTIVE)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 8),

                                /// 🔥 REACTIVE STATUS
                                Obx(() {
                                  final d = controller.rideStatusData.value;

                                  if (d == null) {
                                    return const Text("Loading...");
                                  }

                                  final text = d.acceptRide == true
                                      ? 'Rider has accepted your ride'
                                      : d.ongoingRide == true
                                          ? 'Rider is on the way to pickup'
                                          : d.arrivingRide == true
                                              ? 'Rider arrived'
                                              : d.completeRide == true
                                                  ? 'Ride completed'
                                                  : 'Waiting for driver...';

                                  return Text(
                                    text,
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: FontFamily.poppins,
                                      color: AppColors.darkColor,
                                    ),
                                  );
                                }),
                              ],
                            ),

                            /// TIME BOX (REACTIVE)
                            Obx(() {
                              controller.currentLatitudePosition?.value;
                              controller.currentLongitudePosition?.value;

                              final metrics = RideEtaResolver.resolve(
                                controller: controller,
                                rideStatus: controller.rideStatusData.value,
                              );

                              final isNear = metrics.distanceMeters > 0 &&
                                  metrics.distanceMeters <= 500;

                              return Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isNear
                                      ? Colors.green
                                      : AppColors.darkColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  RideDistanceFormatter.formatDuration(
                                    metrics.durationSeconds,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            }),
                            Obx(() {
                              // Reporting is only offered once the ride is
                              // finished, not mid-trip.
                              final showReport = controller
                                      .rideStatusData.value?.completeRide ==
                                  true;

                              if (!showReport) {
                                debugPrint(
                                  '🚨❌ Report hidden | completeRide=${controller.rideStatusData.value?.completeRide}',
                                );
                                return const SizedBox();
                              }

                              debugPrint(
                                '🚨✅ Report visible | completeRide=true',
                              );

                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.whiteColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadiusGeometry.all(Radius.circular(30.r))
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    vertical: 20.h,
                                    horizontal: 12.h,
                                  ),
                                ),
                                onPressed: () {
                                  Get.toNamed(AppRoutes.reportScreen,arguments: {'rideId' :  controller.rideStatusData.value?.ride?.id});
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_alert_sharp,
                                      color: AppColors.errorColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    SizedBox(width: 10.w),
                                    Text(
                                      'Report',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w600,
                                        fontFamily: FontFamily.poppins,
                                        color: AppColors.errorColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ───────────────── BODY ─────────────────
                  Padding(
                    padding: EdgeInsets.only(
                      left: 12.h,
                      right: 12.h,
                      top: 16.h,
                      // Keeps the action buttons clear of the sheet's bottom
                      // edge and the device's home indicator.
                      bottom: 32.h + MediaQuery.of(context).padding.bottom,
                    ),
                    child: Column(
                      children: [
                        /// DRIVER INFO
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Image.network(
                                    '${ApiUrls.imageBaseUrl}'
                                    '${widget.rideStatus?.driver?.image?.filename}',
                                    height: 62.h,
                                    width: 62.w,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) {
                                      return Image.asset(
                                        Assets.images.defaultImage.path,
                                        height: 62.h,
                                        width: 62.w,
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.rideStatus?.driver?.name ?? '',
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.successColor,
                                      ),
                                    ),
                                    Text(
                                      widget.rideStatus?.driver?.phone ?? '',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () {
                                launchUrl(Uri.parse(
                                  "tel:${widget.rideStatus?.driver?.phone}",
                                ));
                              },
                              child: RepaintBoundary(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.whiteColor,
                                    borderRadius: BorderRadius.circular(50),
                                    border: Border.all(
                                        color: AppColors.greyColor200),
                                  ),
                                  child: SvgPicture.asset(
                                      Assets.icons.driverCardPhone),
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 20.h),

                        /// CAR INFO
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.rideStatus?.driverCar?.carName ?? '',
                                ),
                                Text(
                                  widget.rideStatus?.driverCar
                                          ?.carPlateNumber ??
                                      '',
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        /// COMPLETE BUTTON
                        Obx(() {
                          final complete =
                              controller.rideStatusData.value?.completeRide ==
                                  true;

                          if (!complete) {
                            debugPrint(
                              '🔘❌ Review/Tips/BackToHome HIDDEN | '
                              'completeRide=${controller.rideStatusData.value?.completeRide} '
                              'startRide=${controller.rideStatusData.value?.startRide} '
                              'ride.status=${controller.rideStatusData.value?.ride?.status}',
                            );
                            return const SizedBox();
                          }

                          debugPrint(
                            '🔘✅ Review/Tips/BackToHome VISIBLE | '
                            'completeRide=true rideId=${controller.rideStatusData.value?.ride?.id}',
                          );

                          return Column(
                            children: [
                              if (Get.find<UserController>()
                                      .userModel
                                      .value
                                      ?.userProfile
                                      ?.role ==
                                  AppConstants.passenger)
                                Row(
                                children: [
                                  Flexible(
                                    child: CustomPrimaryButton(
                                      title: 'Review',
                                      onHandler: () {
                                        // ride.driver carries the driver's
                                        // user _id; driverCar.driverId is
                                        // often absent, which left Review and
                                        // Add-to-Favourite with a null id.
                                        Get.toNamed(
                                          AppRoutes.rateReviewDriver,
                                          arguments: {
                                            'name':
                                                widget.rideStatus?.driver?.name,
                                            'driverId': widget.rideStatus
                                                    ?.ride?.driver?.id ??
                                                widget.rideStatus?.driver?.id ??
                                                widget.rideStatus
                                                    ?.driverCar?.driverId,
                                            'rideId':
                                                widget.rideStatus?.ride?.id,
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    width: 8.w,
                                  ),
                                  Flexible(
                                    child: CustomPrimaryButton(
                                      title: 'Tips',
                                      onHandler: () {
                                        _buildTipsShowDialog(context);
                                      },
                                    ),
                                  )
                                ],
                              ),
                              SizedBox(
                                height: 16.h,
                              ),
                              CustomPrimaryButton(
                                title: 'Back to Home',
                                onHandler: () async {
                                  debugPrint('🏠👆 passenger tapped Back to Home');
                                  final rideId =
                                      controller.rideStatusData.value?.ride?.id;
                                  if (rideId != null && rideId.isNotEmpty) {
                                    controller.markRideFinished(rideId);
                                  }
                                  controller.clearRideSession();
                                  final rideController = Get.find<RideController>();
                                  rideController.returnToNormalView();
                                  rideController.isSwippedButtonShow.value = false;
                                  Get.find<GoogleSearchLocationController>()
                                      .isModalOn
                                      .value = false;
                                  await Get.find<UserController>()
                                      .fetchActiveRideStatus();
                                  Get.offAllNamed(AppRoutes.customBottomNavBar);
                                  Get.find<CustomBottomNavBarController>()
                                      .onChange(0);
                                  debugPrint('🏠✅ Back to Home done → navbar home');
                                },
                              )
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Future<dynamic> _buildTipsShowDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
          child: GlassBackgroundWidget(
            borderLeftRightRadius: 24,
            padding: EdgeInsets.all(20.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close Button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.of(dialogContext).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 20.sp,
                        color: AppColors.darkColor,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 8.h),
                CustomText(
                  text: 'Tips',
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryColor,
                  maxline: 2,
                ),
                SizedBox(height: 8.h),
                CustomText(
                  text: 'Enjoyed your ride?',
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryTextColor,
                  maxline: 2,
                ),
                SizedBox(height: 20.h),
                CustomTextField(
                  controller: controller.provideTips,
                  labelText: 'Enter Amount',
                  hintText: 'Enter Amount',
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 12.h),
                Center(
                  child: Text(
                    'Tips will go completely to driver',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      fontFamily: FontFamily.poppins,
                      color: AppColors.secondaryTextColor,
                    ),
                  ),
                ),
                SizedBox(height: 20.h),
                CustomPrimaryButton(
                  title: 'Submit',
                  onHandler: () async {
                    final val = await controller.provideTipsHandler(
                        controller.rideStatusData.value?.ride?.id ?? '');
                    if (val == true && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
