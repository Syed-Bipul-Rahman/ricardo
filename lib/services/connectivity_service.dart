import 'dart:async';
import 'dart:io';

import 'package:get/get.dart';

/// Lightweight reactive connectivity tracker. Uses a DNS lookup to verify
/// actual reachability (Wi-Fi-without-internet returns false), polls every
/// 10s, and exposes `isConnected` as an `RxBool` for `Obx` consumers.
class ConnectivityService extends GetxService {
  final RxBool isConnected = true.obs;
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  Future<bool> _check() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      final connected =
          result.isNotEmpty && result.first.rawAddress.isNotEmpty;
      isConnected.value = connected;
      return connected;
    } catch (_) {
      isConnected.value = false;
      return false;
    }
  }

  /// Fire an out-of-cycle reachability check (e.g., after a failed API call).
  Future<bool> recheck() => _check();

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
