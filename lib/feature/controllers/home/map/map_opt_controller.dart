import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:ricardo/app/helpers/custom_location_helper.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart';
import 'package:ricardo/feature/models/socket/accept_ride_driver_model.dart';
import 'package:ricardo/feature/models/socket/get_ride_driver_location.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/feature/view/home/map/driver_location_service.dart';
import 'package:ricardo/services/api_client.dart';
import 'package:ricardo/app/helpers/snackbar_helper.dart';

class MapOPTController extends GetxController {
  // Controller are here
  RxBool isCurrentMarkerShowOrNot = true.obs;

  UserController? _userController;
  UserController get userController =>
      _userController ??= Get.find<UserController>();
  RxBool showCancelReasonDialog = false.obs;
  final Rx<GetRideDriverLocation?> getRideDriverLocation =
      Rx<GetRideDriverLocation?>(null);
  RxDouble buttonTop = 300.0.obs;
  RxDouble buttonRight = 10.0.obs;

  // Controls Uber-style location button visibility.
  // Hidden by default; shown when the map camera moves away from the user's
  // current position; hidden again once the user taps it.
  RxBool isLocationButtonVisible = false.obs;

  // Set to true while the "go to my location" animation is running so that the
  // camera-move callbacks fired by the animation don't re-show the button.
  bool _isCenteringCamera = false;

  void notifyMapMoved() {
    // Ignore camera events that we triggered ourselves (e.g. animateCamera).
    if (_isCenteringCamera) return;
    isLocationButtonVisible.value = true;
  }

  void hideLocationButton() {
    _isCenteringCamera = true;
    isLocationButtonVisible.value = false;
    // Allow a bit longer than the 2-second camera animation before re-enabling
    // the flag, so we don't accidentally show the button mid-animation.
    Future.delayed(const Duration(milliseconds: 2500), () {
      _isCenteringCamera = false;
    });
  }

  @override
  void onInit() {
    getLocation();
    super.onInit();
  }

  Timer? _rideRequestTimer;
  RxDouble timerProgress = 1.0.obs;
  RxBool isRideRequestExpired = false.obs;

  void startRideRequestTimer() {
    _rideRequestTimer?.cancel();

    final timeoutMinutes =
        int.tryParse(dotenv.env['RIDE_MODAL_EXPIRE_TIME'] ?? '') ?? 2;
    final totalMillis = timeoutMinutes * 60 * 1000;
    final startTime = DateTime.now();

    timerProgress.value = 1.0;
    isRideRequestExpired.value = false;

    _rideRequestTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        final elapsed = DateTime.now().difference(startTime).inMilliseconds;
        final remaining = totalMillis - elapsed;

        if (remaining <= 0) {
          timerProgress.value = 0.0;
          isRideRequestExpired.value = true;
          timer.cancel();
        } else {
          timerProgress.value = remaining / totalMillis;
        }
      },
    );
  }

  void cancelRideRequestTimer() {
    _rideRequestTimer?.cancel();
    _rideRequestTimer = null;
    timerProgress.value = 1.0;
    isRideRequestExpired.value = false;
  }

  //***************************************************
  // ******* Current Location Related work are here****
  // ***************************************************

  RxString currentLocation = 'Fetching location...'.obs;
  RxDouble? currentLatitudePosition = 0.0.obs;
  RxDouble? currentLongitudePosition = 0.0.obs;
  // Heading in degrees clockwise from North. Used to rotate the car marker so
  // it points the way the driver is moving. Stays at the last valid value when
  // the device is stationary (otherwise the icon spins from GPS jitter).
  RxDouble headingDegrees = 0.0.obs;

  Future<void> getLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      currentLatitudePosition?.value = position.latitude;
      currentLongitudePosition?.value = position.longitude;

      // Convert coordinates to address using geocoding
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;

        currentLocation.value =
            '${place.street}, ${place.subLocality}, ${place.locality}';
      }
    } catch (e) {
      // ✅ Fallback to user address from API if location fails
      currentLocation.value = 'Location not available';
    }
  }

//***************************************************
// ******* Offline & Online Related work are here ****
// ***************************************************

  RxBool isDriverSwitchAvailabilityStatus = false.obs;

  Future<void> driverSwitchAvailabilityStatus() async {
    final user = userController.userModel.value;
    final bool previousIsOnline = user?.driverProfile?.isOnline ?? false;

    // Optimistic flip — UI updates instantly, no waiting for the round trip.
    user?.driverProfile?.isOnline = !previousIsOnline;
    userController.userModel.refresh();

    isDriverSwitchAvailabilityStatus.value = true;
    final response = await ApiClient.patch(
      ApiUrls.driverSwitchAvailabilityStatus,
      {
        "location": {
          "type": "Point",
          "coordinates": [
            currentLongitudePosition?.value,
            currentLatitudePosition?.value
          ]
        }
      },
    );
    isDriverSwitchAvailabilityStatus.value = false;

    if (response.statusCode != 200 && response.statusCode != 201) {
      // Revert on failure.
      user?.driverProfile?.isOnline = previousIsOnline;
      userController.userModel.refresh();
      showSnackbar('Error', response.body?['message'] ?? 'Failed to update status');
    }
  }

  //***************************************************
  // ******* Socket Rider Response  ****
  // ***************************************************
  RxBool isPassengerRequest = false.obs;
  Rx<RideDetailsSocketModel?> rideDetailsData =
      Rx<RideDetailsSocketModel?>(null);

  Rx<DateTime?> rideRequestReceivedAt =
      Rx<DateTime?>(null); // tracks when request arrived
  Rx<RideStatusModel?> rideStatusData =
      Rx<RideStatusModel?>(null); // ride-status socket data

  //***************************************************
// *** Socket  Driver Model  Response ****
// ***************************************************
  RxBool acceptedRideDriverDataStatus = false.obs;
  Rx<AcceptRideDriverModel?> acceptedRideDriverData =
      Rx<AcceptRideDriverModel?>(null);

  //***************************************************
  // ******* Book a Ride From the Driver  **************
  // ***************************************************
  final isRideAcceptStatusLoading = false.obs;

  Future<void> rideAcceptRide(String rideId) async {
    isRideAcceptStatusLoading.value = true;
    LatLng currentLatLun = await CustomLocationHelper.getCurrentLocation();

    final response =
        await ApiClient.postData(ApiUrls.rideAcceptRideByRideId(rideId), {
      "coordinates": [currentLatLun.longitude, currentLatLun.latitude]
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      isRideAcceptStatusLoading.value = false;
    } else {
      isRideAcceptStatusLoading.value = false;
      showSnackbar('Error', response.body['message']);
    }
  }

  // ---------------- Tips related work are here
  // -------------------------------------------
  final TextEditingController provideTips = TextEditingController();
  RxBool isLoading = false.obs;
  RxBool isTipsSuccess = false.obs;

  Future<bool> provideTipsHandler(String rideId) async {
    if( rideId.isEmpty ) return false;

    if (provideTips.text.trim().isEmpty) {
      isTipsSuccess.value = false;
      return false;
    }

    try {
      isLoading.value = true;

      final response = await ApiClient.postData(
        ApiUrls.sendTips,
        {
          "amount": provideTips.text.trim(),
          "rideId": rideId,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        isTipsSuccess.value = true;
        provideTips.clear();
        return true;
      } else {
        showSnackbar('Error', response.body['message'],snackPosition: SnackPosition.BOTTOM);
        provideTips.clear();
        isTipsSuccess.value = false;
        return false;
      }
    } catch (e) {
      debugPrint(e.toString());
      isTipsSuccess.value = false;
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  // ------------- Review related work are here
  // -------------------------------------------

  final isAddedFavouriteRiderStatus = false.obs;
  final addedFavourite = false.obs;

  Future<bool> addedFavouriteRide(String driverId) async {
    try {
      isAddedFavouriteRiderStatus.value = true; // ✅ start loading

      final response = await ApiClient.postData(
        ApiUrls.favoriteRider,
        {"driver": driverId},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        addedFavourite.value = true;
        return true;
      } else if (response.statusCode == 400 &&
          response.body['message'] == 'Driver already added to favorites') {
        showSnackbar("Info", "Already added to favorites");
        addedFavourite.value = false;
        return true;
      } else {
        addedFavourite.value = false;
        final message = response.body is Map
            ? response.body['message'] ?? 'Something went wrong'
            : 'Something went wrong';

        showSnackbar('Error', message);
        return false;
      }
    } catch (e) {
      addedFavourite.value = false;
      showSnackbar('Error', e.toString());
      debugPrint(e.toString());
      return false; // ✅ FIXED
    } finally {
      isAddedFavouriteRiderStatus.value = false; // ✅ stop loading
    }
  }

  // Ride Status change are here
  RxBool isRideStatusChangeLoading = false.obs;

  Future<void> rideStatusChange(String rideId, String status) async {
    try {
      isRideStatusChangeLoading.value = true;

      final response = await ApiClient.postData(
          ApiUrls.rideChangeRideStatus(rideId), {"status": status});
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('===================>>>>>>>>>>>>>> Maruf ${response.body}');
      } else {
        showSnackbar('error', response.body['message']);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      isRideStatusChangeLoading.value = false;
    }
  }

  RxBool isRideCanceledLoader = false.obs;
  final TextEditingController? selectedReason = TextEditingController();
  RxBool isResult = false.obs;
  Future<bool> cancelRideByDriverHandler(String rideId) async {
    try {
      isRideCanceledLoader.value = true;
      final response = await ApiClient.postData(
          ApiUrls.cancelRideByDriver(rideId),
          {"cancellationReason": selectedReason?.text});
      if (response.statusCode == 200 || response.statusCode == 201) {
        isResult.value = true;
      } else {
        isResult.value = false;
        showSnackbar('Error', response.body['message']);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      isRideCanceledLoader.value = false;
    }
    return isResult.value;
  }

  //  Driver Service Function are here
  Future<void> driverServiceFun(String rideId) async {
    print('FFFFFFFFFF $rideId');
    // final String? rideId = rideStatusData.value?.ride?.id ??
    //     acceptedRideDriverData.value?.ride?.sId;

    if (rideId == null || rideId.isEmpty) {
      debugPrint('❌ rideId is null or empty, stopping emission');
      DriverLocationService().stop();
      return;
    }

    if (SocketServices.socket == null ||
        SocketServices.socket?.connected == false) {
      debugPrint('❌ Socket not connected, skipping emission start');
      return;
    }

    // Start emitting driver location to backend so it can calculate
    // driverToPickup / driverToDestination distances and emit them back.
    // The get-ride-driver-location listener is owned by connectSocket() and
    // must not be replaced here — replacing it would strip passenger polyline
    // update logic registered there.
    DriverLocationService().startEmitting(rideId);
  }

  //  Complete Related work are here
  RxBool isCompleteRideLoading = false.obs;
  Future<void> completeRideHandler(String rideId, int waitingTime) async {
    try {
      isCompleteRideLoading.value = true;
      final response = await ApiClient.postData(
          ApiUrls.completeRideByDriver(rideId), {"waitingTime": waitingTime});
      if (response.statusCode == 200 || response.statusCode == 201) {

      } else {
        showSnackbar('Error', response.body['message']);
      }
    } catch (e) {
      isCompleteRideLoading.value = false;
    } finally {
      isCompleteRideLoading.value = false;
    }
  }

  @override
  void dispose() {
    provideTips.dispose();
    selectedReason?.dispose();
    _rideRequestTimer?.cancel();
    super.dispose();
  }
}
