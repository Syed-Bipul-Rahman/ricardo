// ignore_for_file: invalid_use_of_protected_member
part of '../../map_screen.dart';

extension _Markers on _MapScreenState {
  Future<void> initMarkers() async {
    customMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      "assets/images/passenger_location_marker.png",
    );
    customCarMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      "assets/images/car_marker.png",
    );
    customUserMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      'assets/images/passenger_marker.png',
    );
    destinationMarker = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(devicePixelRatio: 1.0, size: Size(50, 50)),
      'assets/images/destination_marker.png',
    );
    if (mounted) setState(() {});
  }

  Set<Marker> buildMarkers() {
    final Set<Marker> result = {};

    final currentLat = mapOPTController.currentLatitudePosition?.value ?? 0.0;
    final currentLng = mapOPTController.currentLongitudePosition?.value ?? 0.0;
    final rideStatus = mapOPTController.rideStatusData.value;

    if (currentLat != 0.0 && currentLng != 0.0) {
      // Rotate the car marker to match GPS heading. Anchor at center + flat
      // mode so it rotates around its middle and stays aligned with the road
      // (instead of standing up like a pin) — passenger pin stays unrotated.
      final double heading = mapOPTController.headingDegrees.value;
      final bool isPassenger =
          userController.userModel.value?.userProfile?.role ==
              AppConstants.passenger;
      final BitmapDescriptor selfIcon = isPassenger
          ? (customMarker ?? BitmapDescriptor.defaultMarker)
          : (customCarMarker ?? BitmapDescriptor.defaultMarker);
      final bool inActiveRide = rideStatus?.acceptRide == true ||
          rideStatus?.ongoingRide == true ||
          rideStatus?.arrivingRide == true ||
          rideStatus?.startRide == true ||
          rideStatus?.completeRide == true;
      // During an active ride, both roles see the car icon at the driver's
      // position (preserves prior behavior).
      final BitmapDescriptor activeIcon =
          customCarMarker ?? BitmapDescriptor.defaultMarker;

      result.add(
        Marker(
          markerId: const MarkerId('currentPassenger'),
          position: LatLng(currentLat, currentLng),
          icon: inActiveRide ? activeIcon : selfIcon,
          // Only rotate the car icon — a passenger pin pointing sideways
          // would look wrong.
          rotation: (inActiveRide || !isPassenger) ? heading : 0,
          anchor: (inActiveRide || !isPassenger)
              ? const Offset(0.5, 0.5)
              : const Offset(0.5, 1.0),
          flat: inActiveRide || !isPassenger,
        ),
      );
    }

    for (final m in markers) {
      if (m.markerId.value != 'currentPassenger') {
        result.add(m);
      }
    }

    final bool isRouteActive = markers.any(
      (m) =>
          m.markerId.value == 'Pick-Up-Location' ||
          m.markerId.value == 'Destination' ||
          m.markerId.value == 'pickup_location' ||
          m.markerId.value == 'destination_location',
    );

    final bool showDriverIcons =
        rideController.viewInMapReturn.value || !isRouteActive;

    if (showDriverIcons) {
      final drivers = rideController.drivers;
      for (var driver in drivers) {
        final coords = driver.location?.coordinates;
        if (coords != null && coords.length == 2) {
          result.add(Marker(
            markerId: MarkerId(driver.sId ?? UniqueKey().toString()),
            position: LatLng(coords[1], coords[0]),
            icon: customCarMarker ?? BitmapDescriptor.defaultMarker,
            onTap: () => showDriverInfoDialog(context, driver, rideController),
          ));
        }
      }
    }

    return result;
  }
}
