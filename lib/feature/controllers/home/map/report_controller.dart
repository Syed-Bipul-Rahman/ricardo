import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/services/api_client.dart';

class ReportController extends GetxController{
  final TextEditingController txController = TextEditingController();
  RxInt radioBtnValue = 0.obs;

  RxBool isReportStatus = false.obs;

  Future<bool> reportButtonHandler(String rideId ) async {
    RxBool result = false.obs;
    try{
      if( rideId.isEmpty ) return false;

      isReportStatus.value = true;
      final response = await ApiClient.postData(ApiUrls.reportRideByPassenger,
          {
            "rideId": rideId,
            "report": txController.text.trim(),
          });
      if( response.statusCode == 200 || response.statusCode == 201 ){
        result.value = true;
      }else{
        Get.snackbar('Error', response.body['message']);
        result.value = false;
      }
    }catch(e){
      debugPrint(e.toString());
    }finally{
      isReportStatus.value = false;
    }
    return result.value;
  }

}