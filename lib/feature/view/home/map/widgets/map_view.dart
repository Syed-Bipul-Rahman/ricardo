import 'package:flutter/material.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';

class MapView extends StatelessWidget {
  const MapView({
    super.key,
    required this.mapOPTController,
    required this.currentZoom,
    required this.defaultLocation,
    required this.markersBuilder,
    required this.polylines,
    required this.onMapCreated,
    this.onCameraMove,
  });

  final MapOPTController mapOPTController;
  final double currentZoom;
  final LatLng defaultLocation;
  final Set<Marker> Function() markersBuilder;
  final Set<Polyline> polylines;
  final void Function(GoogleMapController) onMapCreated;
  final void Function(CameraPosition)? onCameraMove;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final mapPadding = EdgeInsets.fromLTRB(
      16,
      (screenHeight * 0.14).clamp(90.0, 140.0),
      16,
      (screenHeight * 0.28).clamp(180.0, 280.0),
    );

    return Obx(
      () {
        final currentLatitude =
            mapOPTController.currentLatitudePosition?.value ?? 0.0;
        final currentLongitude =
            mapOPTController.currentLongitudePosition?.value ?? 0.0;
        final animatedPosition =
            mapOPTController.animatedCurrentMarkerPosition.value;
        final isPassenger = mapOPTController
                .userController.userModel.value?.userProfile?.role ==
            AppConstants.passenger;
        final remoteCoordinates = mapOPTController
            .getRideDriverLocation.value?.driverLocation?.coordinates;
        final remoteDriverPosition =
            mapOPTController.animatedRemoteDriverPosition.value ??
                (remoteCoordinates != null && remoteCoordinates.length >= 2
                    ? LatLng(remoteCoordinates[1], remoteCoordinates[0])
                    : null);
        final circlePosition = isPassenger && remoteDriverPosition != null
            ? remoteDriverPosition
            : (animatedPosition ?? LatLng(currentLatitude, currentLongitude));

        return GoogleMap(
          mapToolbarEnabled: false,
          padding: mapPadding,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          trafficEnabled: false,
          zoomGesturesEnabled: true,
          mapType: MapType.normal,
          buildingsEnabled: true,
          indoorViewEnabled: false,
          initialCameraPosition: CameraPosition(
            target: LatLng(
              (mapOPTController.currentLatitudePosition?.value ?? 0) != 0
                  ? mapOPTController.currentLatitudePosition!.value
                  : defaultLocation.latitude,
              (mapOPTController.currentLongitudePosition?.value ?? 0) != 0
                  ? mapOPTController.currentLongitudePosition!.value
                  : defaultLocation.longitude,
            ),
            zoom: currentZoom,
            bearing: 0,
            tilt: 0,
          ),
          markers: markersBuilder(),
          polylines: polylines,
          onMapCreated: onMapCreated,
          onCameraMove: onCameraMove,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          circles: {
            Circle(
              circleId: const CircleId('currentDriver'),
              center: circlePosition,
              radius: 20,
              strokeColor: Colors.white,
              strokeWidth: 2,
              fillColor: const Color(0xFF006491).withOpacity(0.2),
            ),
          },
        );
      },
    );
  }
}
