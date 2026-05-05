
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:ricardo/feature/models/user_model.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/services/api_client.dart';

class UserController extends GetxController {
  RxBool isBottomModalSheetStatus = false.obs;
  Rx<UserModel?> userModel = Rx<UserModel?>(null);

  RxBool isUserDataLoadingStatus = false.obs;

  /// Returns the HTTP status code from the request. On success, the user is
  /// cached to prefs for offline fallback. On network failure, falls back to
  /// the cached copy if present so the app doesn't bounce to login.
  Future<int?> fetchUser() async {
    isUserDataLoadingStatus.value = true;

    final response = await ApiClient.getData(ApiUrls.getMe);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.body['data'];
      userModel.value = UserModel.fromJson(data);
      update();
      // Persist for offline launches.
      try {
        await PrefsHelper.setString(
            AppConstants.userModelCache, jsonEncode(data));
      } catch (e) {
        debugPrint('userModelCache write failed: $e');
      }
    } else if (userModel.value == null) {
      // Network/server error and no in-memory model — try the disk cache.
      await loadCachedUser();
    }
    isUserDataLoadingStatus.value = false;
    update();
    return response.statusCode;
  }

  /// Hydrate userModel from the on-disk cache (no network). Returns true if
  /// a cached user was loaded.
  Future<bool> loadCachedUser() async {
    final cached = await PrefsHelper.getString(AppConstants.userModelCache);
    if (cached.isEmpty) return false;
    try {
      userModel.value = UserModel.fromJson(jsonDecode(cached));
      update();
      return true;
    } catch (e) {
      debugPrint('userModelCache parse failed: $e');
      return false;
    }
  }

  Future<void> clearCachedUser() async {
    userModel.value = null;
    await PrefsHelper.remove(AppConstants.userModelCache);
  }
  /* ****************************
  * ****** RIDE STATUS RELATED *
  * ****************************/
  // Fetch Ride Status related work are here
  final RxBool isLoadingActiveRideStatus = false.obs;
  MapOPTController? _mapOPTController;
  MapOPTController get mapOPTController => _mapOPTController ??= Get.find<MapOPTController>();
  
  RideController? _rideController;
  RideController get rideController => _rideController ??= Get.find<RideController>();

  RxString activeRideStatus = ''.obs;
  Future<bool?> fetchActiveRideStatus() async{
    try{
      final response = await ApiClient.getData(ApiUrls.getActiveRide);
      print('==========================================STatus');
      print('========================>>>>>>>>>>>> ${response.body}');
      if( response.statusCode == 200 || response.statusCode == 201 ){
        activeRideStatus.value = response.body['data']['status'];
        print('====================>>>>>>>>>>>> $activeRideStatus');
        return true;
      }else{
        return false;
      }
    }catch(e){
      debugPrint(e.toString());
    }finally{

    }
    return null;
  }

}