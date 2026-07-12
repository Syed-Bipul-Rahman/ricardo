import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ricardo/feature/models/wallet/withdraw_settings_model.dart';
import 'package:ricardo/services/api_client.dart';
import 'package:ricardo/services/api_urls.dart';

class AppSettingsController extends GetxController {
  RxBool isLoading = false.obs;
  Rx<WithdrawSettingsModel?> settings = Rx<WithdrawSettingsModel?>(null);

  double get perMilePrice => settings.value?.perMilePrice ?? 1;
  double get waitingTimeCharge => settings.value?.waitingTimeCharge ?? 0;
  double get cancellationFeePerMile =>
      settings.value?.cancellationFeePerMile ?? 0;
  double get platformFeePercentage =>
      settings.value?.platformFeePercentage ?? 0;
  double get minimumWithdrawAmount =>
      settings.value?.minimumWithdrawAmount ?? 0;
  bool get isWithdrawDisabled => settings.value?.isWithdrawEnabled == true;
  List<String> get freeWithdrawDays =>
      settings.value?.freeWithdrawDays ?? [];

  @override
  void onInit() {
    super.onInit();
    fetchSettings();
  }

  Future<void> fetchSettings() async {
    if (isLoading.value) return;

    try {
      isLoading.value = true;
      final response = await ApiClient.getData(ApiUrls.withdrawSettings);
      if (response.statusCode == 200 && response.body['data'] != null) {
        settings.value =
            WithdrawSettingsModel.fromJson(response.body['data']);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      isLoading.value = false;
    }
  }
}
