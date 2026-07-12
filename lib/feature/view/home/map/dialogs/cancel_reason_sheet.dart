import 'package:flutter/material.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';

void showCancelReasonSheet(
  BuildContext context, {
  required MapOPTController mapOPTController,
  required Future<void> Function() onConfirmed,
}) {
  final reasons = [
    'Passenger no show',
    'Difficult pickup location',
    'Unaccompanied minor',
    'No car seat',
    'Too many bags',
    'Other safety concern',
    'Destination changed',
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white.withOpacity(0.3),
    barrierColor: Colors.transparent,
    builder: (context) {
      String? selectedReason;
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return GlassBackgroundWidget(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 30,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close,
                            size: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Choose Reason For Cancelling',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                Divider(color: Colors.grey.shade300),
                const SizedBox(height: 8),
                ...reasons.map((reason) => GestureDetector(
                      onTap: () {
                        setDialogState(() => selectedReason = reason);
                        mapOPTController.selectedReason?.text = reason;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selectedReason == reason
                                      ? Colors.green
                                      : Colors.grey,
                                  width: 2,
                                ),
                                color: selectedReason == reason
                                    ? Colors.green
                                    : Colors.transparent,
                              ),
                              child: selectedReason == reason
                                  ? const Icon(Icons.check,
                                      size: 13, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Text(reason,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      disabledBackgroundColor: Colors.red.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50)),
                    ),
                    onPressed: selectedReason == null
                        ? null
                        : () async {
                            final rideId = mapOPTController
                                .rideStatusData.value?.ride?.id;
                            if (rideId == null) {
                              debugPrint('❌ Ride ID is null');
                              return;
                            }
                            final success = await mapOPTController
                                .cancelRideByDriverHandler(rideId);
                            if (cnt == true) {
                              await onConfirmed();
                              if (context.mounted) Navigator.pop(context);
                            if (success == true) {
                              onConfirmed();
                              Navigator.pop(context);
                            }
                          },
                    child: Obx(() {
                      if (mapOPTController.isRideCanceledLoader.value) {
                        return const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        );
                      }
                      return const Text(
                        'Cancel Ride',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
