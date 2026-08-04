import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:ricardo/app/helpers/custom_location_helper.dart';
import 'package:ricardo/app/helpers/snackbar_helper.dart';
import 'package:ricardo/feature/models/home/ride_status_model.dart';
import 'package:ricardo/feature/models/socket/accept_ride_driver_model.dart';
import 'package:ricardo/feature/models/socket/get_ride_driver_location.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';
import 'package:ricardo/feature/view/home/map/driver_location_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ricardo/services/direction_services.dart';
import 'package:ricardo/services/api_client.dart';

class MapOPTController extends GetxController {
  // Controller are here
  RxBool isCurrentMarkerShowOrNot = true.obs;

  UserController? _userController;
  UserController get userController =>
      _userController ??= Get.find<UserController>();
  RxBool showCancelReasonDialog = false.obs;
  final Rx<GetRideDriverLocation?> getRideDriverLocation =
      Rx<GetRideDriverLocation?>(null);
  final prefetchedPickupDistance = 0.obs;
  final prefetchedPickupDuration = 0.obs;
  final prefetchedDestinationDistance = 0.obs;
  final prefetchedDestinationDuration = 0.obs;
  final Rxn<DateTime> lastDriverLocationSocketAt = Rxn<DateTime>();
  DateTime? _lastGetDriverLocationEmitAt;
  Timer? _rideLocationSyncTimer;
  String? _syncingRideId;
  String? _lastFinishedRideId;
  DateTime? _lastFinishedAt;
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
    if (rideId.isEmpty) {
      showSnackbar('Error', 'Ride id is missing');
      return;
    }

    isRideAcceptStatusLoading.value = true;
    LatLng currentLatLun = await CustomLocationHelper.getCurrentLocation();

    final response =
        await ApiClient.postData(ApiUrls.rideAcceptRideByRideId(rideId), {
      "coordinates": [currentLatLun.longitude, currentLatLun.latitude]
    });

    if (response.statusCode == 200 || response.statusCode == 201) {
      isRideAcceptStatusLoading.value = false;
      isPassengerRequest.value = false;
      rideDetailsData.value = null;
      cancelRideRequestTimer();
      await driverServiceFun(rideId);
      await prefetchPickupRouteEstimate();
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
  final TextEditingController selectedReason = TextEditingController();
  RxBool isResult = false.obs;
  String? cancelRideErrorMessage;

  Future<bool> cancelRideByDriverHandler(String rideId) async {
    cancelRideErrorMessage = null;

    try {
      isRideCanceledLoader.value = true;
      isResult.value = false;

      final response = await ApiClient.postData(
        ApiUrls.cancelRideByDriver(rideId),
        {"cancellationReason": selectedReason.text.trim()},
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        isResult.value = true;
        selectedReason.clear();
        return true;
      }

      isResult.value = false;
      if (response.body is Map) {
        cancelRideErrorMessage = response.body['message']?.toString();
      }
      return false;
    } catch (e) {
      debugPrint(e.toString());
      isResult.value = false;
      return false;
    } finally {
      isRideCanceledLoader.value = false;
    }
  }

  //  Driver Service Function are here
  void clearPrefetchedRouteEstimates() {
    prefetchedPickupDistance.value = 0;
    prefetchedPickupDuration.value = 0;
    prefetchedDestinationDistance.value = 0;
    prefetchedDestinationDuration.value = 0;
    lastDriverLocationSocketAt.value = null;
    _lastGetDriverLocationEmitAt = null;
  }

  bool get isInActiveRide {
    final status = rideStatusData.value;
    if (status == null) return false;
    return status.acceptRide == true ||
        status.ongoingRide == true ||
        status.arrivingRide == true ||
        status.startRide == true;
  }

  String? get activeRideId {
    final fromStatus = rideStatusData.value?.ride?.id;
    if (fromStatus != null && fromStatus.isNotEmpty) return fromStatus;
    final fromDriverAccept = acceptedRideDriverData.value?.ride?.sId;
    if (fromDriverAccept != null && fromDriverAccept.isNotEmpty) {
      return fromDriverAccept;
    }
    return null;
  }

  void markRideFinished(String rideId) {
    if (rideId.isEmpty) return;
    _lastFinishedRideId = rideId;
    _lastFinishedAt = DateTime.now();
  }

  bool shouldIgnoreRideStatus(String? rideId) {
    if (rideId == null || rideId.isEmpty || _lastFinishedRideId == null) {
      return false;
    }
    if (_lastFinishedRideId != rideId) return false;
    final finishedAt = _lastFinishedAt;
    if (finishedAt == null) return false;
    return DateTime.now().difference(finishedAt) < const Duration(minutes: 2);
  }

  void refreshRideObservables() {
    rideStatusData.refresh();
    acceptedRideDriverData.refresh();
    acceptedRideDriverDataStatus.refresh();
    isPassengerRequest.refresh();
    rideDetailsData.refresh();
    getRideDriverLocation.refresh();
    isCompleteRideLoading.refresh();
    isRideStatusChangeLoading.refresh();
    update();
  }

  void clearRideSession() {
    stopRideLocationSync();
    final rideController = Get.find<RideController>();
    rideController.isRideAccepted.value = false;
    rideController.acceptRideModel.value = null;
    rideController.drivers.clear();
    acceptedRideDriverDataStatus.value = false;
    acceptedRideDriverData.value = null;
    isPassengerRequest.value = false;
    isCurrentMarkerShowOrNot.value = true;
    rideStatusData.value = null;
    rideRequestReceivedAt.value = null;
    rideDetailsData.value = null;
    getRideDriverLocation.value = null;
    showCancelReasonDialog.value = false;
    clearPrefetchedRouteEstimates();
    userController.activeRideStatus.value = '';
    PrefsHelper.setString('status', '');
    PrefsHelper.setString('ride-accepted-data', '');
    PrefsHelper.setString('driver-status', '');
    PrefsHelper.setString('ride-accepted-driver-data', '');
    refreshRideObservables();
    rideController.isRideAccepted.refresh();
    rideController.acceptRideModel.refresh();
    rideController.update();
    userController.update();
  }

  bool get isDriverLocationSocketFresh {
    final at = lastDriverLocationSocketAt.value;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(seconds: 45);
  }

  void markDriverLocationSocketReceived() {
    lastDriverLocationSocketAt.value = DateTime.now();
  }

  /// Both passenger and driver emit this; backend replies on the same socket
  /// with [get-ride-driver-location].
  void maybeEmitGetDriverLocation(String rideId) {
    if (rideId.isEmpty || !SocketServices.isConnected) return;

    final now = DateTime.now();
    if (_lastGetDriverLocationEmitAt != null &&
        now.difference(_lastGetDriverLocationEmitAt!) <
            const Duration(seconds: 3)) {
      return;
    }

    _lastGetDriverLocationEmitAt = now;
    SocketServices.emit('get-driver-location', {'rideId': rideId});
  }

  void stopRideLocationSync() {
    _rideLocationSyncTimer?.cancel();
    _rideLocationSyncTimer = null;
    _syncingRideId = null;
    DriverLocationService().stop();
  }

  Future<void> startRideLocationSync(String rideId) async {
    if (rideId.isEmpty) {
      stopRideLocationSync();
      return;
    }

    if (!SocketServices.isConnected) {
      debugPrint('❌ Socket not connected, skipping ride location sync');
      return;
    }

    final isDriver = userController.userModel.value?.userProfile?.role ==
        AppConstants.driver;

    if (_syncingRideId == rideId &&
        (isDriver ? DriverLocationService().isRunning : _rideLocationSyncTimer != null)) {
      maybeEmitGetDriverLocation(rideId);
      return;
    }

    stopRideLocationSync();
    _syncingRideId = rideId;

    if (isDriver) {
      DriverLocationService().startEmitting(rideId);
    } else {
      _rideLocationSyncTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => maybeEmitGetDriverLocation(rideId),
      );
    }

    maybeEmitGetDriverLocation(rideId);
  }

  void resumeRideLocationSyncIfNeeded() {
    final rideId = activeRideId;
    if (rideId != null && isInActiveRide) {
      startRideLocationSync(rideId);
    }
  }

  Future<void> prefetchPickupRouteEstimate() async {
    final pickupCoords = rideStatusData.value?.ride?.pickupLocation?.coordinates ??
        acceptedRideDriverData.value?.ride?.pickupLocation?.coordinates;
    if (pickupCoords == null || pickupCoords.length < 2) return;

    final driverLat = currentLatitudePosition?.value;
    final driverLng = currentLongitudePosition?.value;
    if (driverLat == null || driverLng == null || driverLat == 0 || driverLng == 0) {
      return;
    }

    final metrics = await DirectionsService.getRouteMetrics(
      LatLng(driverLat, driverLng),
      LatLng(pickupCoords[1], pickupCoords[0]),
    );
    if (metrics == null) return;

    prefetchedPickupDistance.value = metrics.distanceMeters;
    prefetchedPickupDuration.value = metrics.durationSeconds;
  }

  Future<void> prefetchDestinationRouteEstimate() async {
    final destinationCoords =
        rideStatusData.value?.ride?.destinationLocation?.coordinates ??
            acceptedRideDriverData.value?.ride?.destinationLocation?.coordinates;
    if (destinationCoords == null || destinationCoords.length < 2) return;

    final driverLat = currentLatitudePosition?.value;
    final driverLng = currentLongitudePosition?.value;
    if (driverLat == null || driverLng == null || driverLat == 0 || driverLng == 0) {
      return;
    }

    final metrics = await DirectionsService.getRouteMetrics(
      LatLng(driverLat, driverLng),
      LatLng(destinationCoords[1], destinationCoords[0]),
    );
    if (metrics == null) return;

    prefetchedDestinationDistance.value = metrics.distanceMeters;
    prefetchedDestinationDuration.value = metrics.durationSeconds;
  }

  Future<void> driverServiceFun(String rideId) async {
    await startRideLocationSync(rideId);
  }

  //  Complete Related work are here
  RxBool isCompleteRideLoading = false.obs;
  Future<bool> completeRideHandler(String rideId, int waitingTime) async {
    try {
      isCompleteRideLoading.value = true;
      debugPrint('🚗🏁 driver complete API start | rideId=$rideId');
      final response = await ApiClient.postData(
          ApiUrls.completeRideByDriver(rideId), {"waitingTime": waitingTime});
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('🚗✅ driver complete API success | body=${response.body}');
        markRideFinished(rideId);
        stopRideLocationSync();
        return true;
      } else {
        debugPrint(
          '🚗❌ driver complete API failed | status=${response.statusCode} body=${response.body}',
        );
        final message = response.body is Map
            ? response.body['message'] ?? 'Something went wrong'
            : 'Something went wrong';
        showSnackbar('Error', message);
        return false;
      }
    } catch (e) {
      debugPrint('🚗❌ driver complete API error → $e');
      return false;
    } finally {
      isCompleteRideLoading.value = false;
    }
  }

  @override
  void onClose() {
    stopRideLocationSync();
    provideTips.dispose();
    selectedReason.dispose();
    _rideRequestTimer?.cancel();
    super.onClose();
  }
}
