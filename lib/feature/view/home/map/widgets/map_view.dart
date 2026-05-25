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
  });

  final MapOPTController mapOPTController;
  final double currentZoom;
  final LatLng defaultLocation;
  final Set<Marker> Function() markersBuilder;
  final Set<Polyline> polylines;
  final void Function(GoogleMapController) onMapCreated;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => GoogleMap(
        mapToolbarEnabled: false,
        scrollGesturesEnabled: true,
        rotateGesturesEnabled: true,
        trafficEnabled: false,
        zoomGesturesEnabled: true,
        mapType: MapType.normal,
        initialCameraPosition: CameraPosition(
          target: LatLng(
            mapOPTController.currentLatitudePosition?.value ??
                defaultLocation.latitude,
            mapOPTController.currentLongitudePosition?.value ??
                defaultLocation.longitude,
          ),
          zoom: currentZoom,
        ),
        markers: markersBuilder(),
        polylines: polylines,
        onMapCreated: onMapCreated,
        // myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
        compassEnabled: false,
        circles: {
          Circle(
            circleId: const CircleId('currentDriver'),
            center: LatLng(
              mapOPTController.currentLatitudePosition?.value ?? 0.0,
              mapOPTController.currentLongitudePosition?.value ?? 0.0,
            ),
            radius: 30,
            strokeColor: Colors.white,
            strokeWidth: 2,
            fillColor: const Color(0xFF006491).withOpacity(0.2),
          ),
        },
      ),
    );
  }
}
