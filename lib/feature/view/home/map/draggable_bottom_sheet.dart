import 'package:flutter/material.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';

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

      return DraggableScrollableSheet(
        initialChildSize: 0.40,
        minChildSize: 0.40,
        maxChildSize: (isComplete || isArriving) ? 0.45 : 0.5,
        expand: false,
        builder: (context, scrollController) {
          return GlassBackgroundWidget(
            blurNumber: 25,
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
                              final t = controller.getRideDriverLocation.value
                                  ?.userToDriver?.time?.value;

                              final d = controller.getRideDriverLocation.value
                                  ?.userToDriver?.distance?.value;

                              final isNear = (t == 0 || (d ?? 9999) <= 500);

                              return Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isNear
                                      ? Colors.green
                                      : AppColors.darkColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  t == null
                                      ? "Loading..."
                                      : t > 3600
                                          ? "$t"
                                          : "$t Min",
                                  style: const TextStyle(
                                    color: Colors.white,
                                  ),
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
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.h,
                      vertical: 16.h,
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
                              child: const Icon(Icons.call),
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
                                  '${widget.rideStatus?.driverCar?.numberOfSeat ?? 0} Seat',
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

                          if (!complete) return const SizedBox();

                          return CustomPrimaryButton(
                            title: 'Provide a review',
                            onHandler: () {
                              Get.toNamed(
                                AppRoutes.rateReviewDriver,
                                arguments: {
                                  'name': widget.rideStatus?.driver?.name,
                                  'driverId':
                                      widget.rideStatus?.driverCar?.driverId,
                                  'rideId': widget.rideStatus?.ride?.id,
                                },
                              );
                            },
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
}
