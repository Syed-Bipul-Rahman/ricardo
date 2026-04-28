import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/services/api_client.dart';

class RateAndReviewController extends GetxController{
  final TextEditingController feedBackTEController = TextEditingController();
  RxDouble driverRating = 0.0.obs;
  
  RxBool isRattingLoading = false.obs;
  Future<bool> rateAndReviewDriverHandler( String rideId, String driverId) async {
    RxBool result = false.obs;
    print('====================== $rideId');
    print('====================== $driverId');

    try{
      isRattingLoading.value = true;
      final response = await ApiClient.postData(ApiUrls.ratingCreate,{
        "rideId": rideId,
        "givenTo": driverId,
        "targetType": "driver",
        "rating": driverRating.value,
        "comment": feedBackTEController.text.trim(),
        "tags": []
      },
      );
      if( response.statusCode == 200 || response.statusCode == 201 ){
        result.value = true;
      }else{
        result.value = false;
      }
    }catch(e){
      debugPrint(e.toString());
      isRattingLoading.value = false;
    }finally{
      isRattingLoading.value = false;
    }
    return result.value;
  }

}