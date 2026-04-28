
import 'package:flutter/cupertino.dart';
import 'package:ricardo/feature/models/user_model.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/services/api_client.dart';

class UserController extends GetxController {
  RxBool isBottomModalSheetStatus = false.obs;
  Rx<UserModel?> userModel = Rx<UserModel?>(null);

  RxBool isUserDataLoadingStatus = false.obs;

  Future<void> fetchUser() async {
    isUserDataLoadingStatus.value = true;

    final response = await ApiClient.getData(ApiUrls.getMe);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = response.body['data'];
      userModel.value = UserModel.fromJson(data);
      update();
    }
    isUserDataLoadingStatus.value = false;
    update();
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