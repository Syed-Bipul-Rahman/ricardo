import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:ricardo/app/utils/app_constants.dart';
import 'package:ricardo/feature/controllers/history/history_controller.dart';
import 'package:ricardo/feature/controllers/user_controller.dart';
import 'package:ricardo/services/api_client.dart';
import 'package:ricardo/services/api_urls.dart';

class RateAndReviewController extends GetxController {
  final TextEditingController feedBackTEController = TextEditingController();
  RxDouble driverRating = 0.0.obs;
  RxString errorMessage = ''.obs;
  RxBool isRattingLoading = false.obs;

  Future<bool> rateAndReviewDriverHandler(String rideId, String driverId) async {
    final role = Get.find<UserController>().userModel.value?.userProfile?.role;
    if (role != AppConstants.passenger) {
      errorMessage.value = 'Only passengers can submit a review';
      return false;
    }

    try {
      isRattingLoading.value = true;
      errorMessage.value = '';

      final response = await ApiClient.postData(ApiUrls.ratingCreate, {
        "rideId": rideId,
        "givenTo": driverId,
        "targetType": "driver",
        "rating": driverRating.value,
        "comment": feedBackTEController.text.trim(),
        "tags": []
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        final reviewId = response.body['data']?['_id']?.toString() ??
            response.body['data']?['id']?.toString();

        if (Get.isRegistered<HistoryController>()) {
          Get.find<HistoryController>().markRideAsReviewed(
            rideId,
            reviewId: reviewId,
          );
        }

        clearForm();
        return true;
      }

      errorMessage.value = response.body['message']?.toString() ??
          response.statusText ??
          'Something went wrong';
      return false;
    } catch (e) {
      debugPrint(e.toString());
      errorMessage.value = 'Something went wrong';
      return false;
    } finally {
      isRattingLoading.value = false;
    }
  }

  void clearForm() {
    feedBackTEController.clear();
    driverRating.value = 0.0;
    errorMessage.value = '';
  }

  @override
  void onClose() {
    feedBackTEController.dispose();
    super.onClose();
  }
}
