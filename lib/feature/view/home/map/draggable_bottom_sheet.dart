import 'package:flutter/material.dart';
import 'package:ricardo/app/helpers/ride_distance_formatter.dart';
import 'package:ricardo/app/helpers/ride_eta_resolver.dart';
import 'package:ricardo/app/helpers/snackbar_helper.dart';
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

      debugPrint(
        '🧳📋 bottom sheet build | completeRide=${data?.completeRide} '
        'startRide=${data?.startRide} isComplete=$isComplete rideId=${data?.ride?.id}',
      );

      return DraggableScrollableSheet(
        initialChildSize: isComplete ? 0.56 : 0.42,
        minChildSize: 0.12,
        maxChildSize: isComplete ? 0.78 : 0.62,
        expand: false,
        builder: (context, scrollController) {
          final rideData = data ?? widget.rideStatus;
          return GlassBackgroundWidget(
            blurNumber: 20,
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildSheetHeader(rideData),
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
                        _buildDriverCard(rideData),
                        SizedBox(height: 12.h),
                        _buildVehicleCard(rideData),

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
                                Obx(() {
                                  final liveRide =
                                      controller.rideStatusData.value;
                                  final reviewId = liveRide?.ride?.reviewId;
                                  final alreadyReviewed = reviewId != null &&
                                      reviewId.toString().isNotEmpty;
                                  final rideId = liveRide?.ride?.id;
                                  // Touch the set so Obx rebuilds after tip success.
                                  final tippedIds = controller.tippedRideIds;
                                  final alreadyTipped = rideId != null &&
                                      tippedIds.contains(rideId);
                                  final driverId = liveRide?.ride?.driver?.id ??
                                      liveRide?.driver?.id ??
                                      liveRide?.driverCar?.driverId;

                                  return Row(
                                    children: [
                                      Flexible(
                                        child: CustomPrimaryButton(
                                          title: alreadyReviewed
                                              ? 'Reviewed'
                                              : 'Review',
                                          onHandler: alreadyReviewed
                                              ? null
                                              : () {
                                                  controller
                                                      .prepareFavouriteForDriver(
                                                    driverId,
                                                  );
                                                  Get.toNamed(
                                                    AppRoutes.rateReviewDriver,
                                                    arguments: {
                                                      'name':
                                                          liveRide?.driver?.name,
                                                      'driverId': driverId,
                                                      'rideId': rideId,
                                                      'alreadyReviewed':
                                                          alreadyReviewed,
                                                    },
                                                  );
                                                },
                                        ),
                                      ),
                                      SizedBox(width: 8.w),
                                      Flexible(
                                        child: CustomPrimaryButton(
                                          title: alreadyTipped
                                              ? 'Tipped'
                                              : 'Tips',
                                          onHandler: alreadyTipped
                                              ? null
                                              : () {
                                                  _buildTipsShowDialog(context);
                                                },
                                        ),
                                      )
                                    ],
                                  );
                                }),
                              SizedBox(
                                height: 16.h,
                              ),
                              CustomPrimaryButton(
                                title: 'Back to Home',
                                onHandler: () async {
                                  debugPrint(
                                      '🏠👆 passenger tapped Back to Home');
                                  final rideId =
                                      controller.rideStatusData.value?.ride?.id;
                                  if (rideId != null && rideId.isNotEmpty) {
                                    controller.markRideFinished(rideId);
                                  }
                                  controller.clearRideSession();
                                  final rideController =
                                      Get.find<RideController>();
                                  rideController.returnToNormalView();
                                  rideController.isSwippedButtonShow.value =
                                      false;
                                  Get.find<GoogleSearchLocationController>()
                                      .isModalOn
                                      .value = false;
                                  await Get.find<UserController>()
                                      .fetchActiveRideStatus();
                                  Get.offAllNamed(AppRoutes.customBottomNavBar);
                                  Get.find<CustomBottomNavBarController>()
                                      .onChange(0);
                                  debugPrint(
                                      '🏠✅ Back to Home done → navbar home');
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

  Widget _buildSheetHeader(RideStatusModel? data) {
    controller.currentLatitudePosition?.value;
    controller.currentLongitudePosition?.value;
    final metrics = RideEtaResolver.resolve(
      controller: controller,
      rideStatus: data,
    );
    final isComplete = data?.completeRide == true;
    final isNear = metrics.distanceMeters > 0 && metrics.distanceMeters <= 500;

    final String statusText;
    final IconData statusIcon;
    final Color statusColor;
    if (data == null) {
      statusText = 'Updating your ride';
      statusIcon = Icons.sync_rounded;
      statusColor = AppColors.darkColor;
    } else if (data.completeRide == true) {
      statusText = 'Ride completed';
      statusIcon = Icons.check_circle_rounded;
      statusColor = AppColors.successColor;
    } else if (data.arrivingRide == true) {
      statusText = 'Your driver has arrived';
      statusIcon = Icons.location_on_rounded;
      statusColor = AppColors.successColor;
    } else if (data.startRide == true) {
      statusText = 'Heading to your destination';
      statusIcon = Icons.route_rounded;
      statusColor = AppColors.primaryColor;
    } else if (data.ongoingRide == true) {
      statusText = 'Driver is heading to pickup';
      statusIcon = Icons.local_taxi_rounded;
      statusColor = AppColors.primaryColor;
    } else {
      statusText = 'Driver accepted your ride';
      statusIcon = Icons.thumb_up_alt_rounded;
      statusColor = AppColors.primaryColor;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 10.h, 18.w, 16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 44.w,
            height: 5.h,
            decoration: BoxDecoration(
              color: const Color(0xFFD7D9DE),
              borderRadius: BorderRadius.circular(20.r),
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Container(
                width: 38.r,
                height: 38.r,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(statusIcon, color: statusColor, size: 21.r),
              ),
              SizedBox(width: 11.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        fontFamily: FontFamily.poppins,
                        color: AppColors.darkColor,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      isComplete
                          ? 'Thank you for riding with us'
                          : 'Live trip status',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isComplete) ...[
                SizedBox(width: 10.w),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: isNear
                        ? AppColors.successColor.withValues(alpha: 0.10)
                        : const Color(0xFFF2F3F5),
                    borderRadius: BorderRadius.circular(30.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 15.r,
                        color: isNear
                            ? AppColors.successColor
                            : AppColors.darkColor,
                      ),
                      SizedBox(width: 5.w),
                      Text(
                        RideDistanceFormatter.formatDuration(
                          metrics.durationSeconds,
                        ),
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: isNear
                              ? AppColors.successColor
                              : AppColors.darkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (isComplete)
                Material(
                  color: AppColors.errorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(22.r),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22.r),
                    onTap: () {
                      Get.toNamed(
                        AppRoutes.reportScreen,
                        arguments: {'rideId': data?.ride?.id},
                      );
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.w,
                        vertical: 8.h,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.outlined_flag_rounded,
                            size: 16.r,
                            color: AppColors.errorColor,
                          ),
                          SizedBox(width: 5.w),
                          Text(
                            'Report',
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w700,
                              fontFamily: FontFamily.poppins,
                              color: AppColors.errorColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(RideStatusModel? data) {
    final driver = data?.driver;
    final imageName = driver?.image?.filename;
    final imageUrl = imageName != null && imageName.isNotEmpty
        ? '${ApiUrls.imageBaseUrl}$imageName'
        : null;
    final phone = driver?.phone ?? '';
    final rating = driver?.averageRating ?? 0;

    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: const Color(0xFFEDEEF1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primaryColor.withValues(alpha: 0.25),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: imageUrl == null
                      ? Image.asset(
                          Assets.images.defaultImage.path,
                          height: 62.r,
                          width: 62.r,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          imageUrl,
                          height: 62.r,
                          width: 62.r,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Image.asset(
                            Assets.images.defaultImage.path,
                            height: 62.r,
                            width: 62.r,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: 14.r,
                  height: 14.r,
                  decoration: BoxDecoration(
                    color: AppColors.successColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(width: 13.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver?.name?.isNotEmpty == true
                      ? driver!.name!
                      : 'Your driver',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkColor,
                    fontFamily: FontFamily.poppins,
                  ),
                ),
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Icon(Icons.star_rounded,
                        size: 17.r, color: const Color(0xFFFFB020)),
                    SizedBox(width: 3.w),
                    Text(
                      rating > 0 ? rating.toStringAsFixed(1) : 'New',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryTextColor,
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      Container(
                        width: 3.r,
                        height: 3.r,
                        margin: EdgeInsets.symmetric(horizontal: 8.w),
                        decoration: const BoxDecoration(
                          color: Color(0xFFB1B4BB),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Material(
            color: AppColors.primaryColor,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: phone.isEmpty
                  ? null
                  : () => launchUrl(Uri.parse('tel:$phone')),
              child: Padding(
                padding: EdgeInsets.all(12.r),
                child: Icon(
                  Icons.call_rounded,
                  size: 22.r,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(RideStatusModel? data) {
    final carName = data?.driverCar?.carName;
    final plateNumber = data?.driverCar?.carPlateNumber;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 13.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Row(
        children: [
          Container(
            width: 44.r,
            height: 44.r,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13.r),
            ),
            child: Icon(
              Icons.directions_car_filled_rounded,
              color: AppColors.darkColor,
              size: 25.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  carName?.isNotEmpty == true ? carName! : 'Driver vehicle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkColor,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  'Confirm the plate before entering',
                  style: TextStyle(
                    fontSize: 10.5.sp,
                    color: AppColors.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          if (plateNumber?.isNotEmpty == true)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 7.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: const Color(0xFFD8DADE)),
              ),
              child: Text(
                plateNumber!.toUpperCase(),
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: AppColors.darkColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<dynamic> _buildTipsShowDialog(BuildContext context) {
    const presets = ['5', '10', '15', '20'];
    controller.provideTips.clear();
    final selectedPreset = Rxn<String>();

    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 22.w),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 20.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40.r,
                        height: 40.r,
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.volunteer_activism_rounded,
                          color: AppColors.primaryColor,
                          size: 22.r,
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Say thanks with a tip',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w700,
                                fontFamily: FontFamily.poppins,
                                color: AppColors.darkColor,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              '100% goes to your driver',
                              style: TextStyle(
                                fontSize: 11.5.sp,
                                color: AppColors.secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          if (controller.isLoading.value) return;
                          Navigator.of(dialogContext).pop();
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.secondaryTextColor,
                          size: 22.r,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18.h),
                  Obx(() {
                    final selected = selectedPreset.value;
                    return Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: presets.map((amount) {
                        final isSelected = selected == amount;
                        return InkWell(
                          borderRadius: BorderRadius.circular(30.r),
                          onTap: controller.isLoading.value
                              ? null
                              : () {
                                  selectedPreset.value = amount;
                                  controller.provideTips.text = amount;
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 10.h,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primaryColor
                                  : const Color(0xFFF3F5F7),
                              borderRadius: BorderRadius.circular(30.r),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primaryColor
                                    : const Color(0xFFE2E5EA),
                              ),
                            ),
                            child: Text(
                              amount,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.darkColor,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  }),
                  SizedBox(height: 16.h),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Or enter a custom amount',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryTextColor,
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  CustomTextField(
                    controller: controller.provideTips,
                    labelText: 'Amount',
                    hintText: 'e.g. 25',
                    keyboardType: TextInputType.number,
                    onChanged: (_) {
                      final typed = controller.provideTips.text.trim();
                      if (!presets.contains(typed)) {
                        selectedPreset.value = null;
                      } else {
                        selectedPreset.value = typed;
                      }
                    },
                  ),
                  SizedBox(height: 20.h),
                  Obx(() {
                    final loading = controller.isLoading.value;
                    return CustomPrimaryButton(
                      title: 'Send Tip',
                      isLoading: loading,
                      onHandler: loading
                          ? null
                          : () async {
                              final rideId =
                                  controller.rideStatusData.value?.ride?.id ??
                                      '';
                              final ok =
                                  await controller.provideTipsHandler(rideId);
                              if (ok && dialogContext.mounted) {
                                Navigator.of(dialogContext).pop();
                                showSnackbar(
                                  'Thank you',
                                  'Your tip was sent to the driver',
                                  snackPosition: SnackPosition.BOTTOM,
                                );
                              }
                            },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
