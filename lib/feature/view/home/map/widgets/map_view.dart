import 'package:flutter/material.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';

const String _uberInspiredMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#E9ECEF"}]
  },
  {
    "elementType": "labels.icon",
    "stylers": [{"visibility": "off"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#555B62"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#F5F6F7"}, {"weight": 3}]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#C5C9CD"}]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#3F4247"}, {"weight": 1}]
  },
  {
    "featureType": "landscape",
    "elementType": "geometry",
    "stylers": [{"color": "#ECEFF1"}]
  },
  {
    "featureType": "poi",
    "stylers": [{"visibility": "off"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{"visibility": "on"}, {"color": "#DCE9DD"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#FFFFFF"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#CCD1D5"}, {"weight": 1.1}]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#5D636A"}]
  },
  {
    "featureType": "road.local",
    "elementType": "geometry",
    "stylers": [{"color": "#FFFFFF"}, {"weight": 1}]
  },
  {
    "featureType": "road.local",
    "elementType": "geometry.stroke",
    "stylers": [{"visibility": "on"}, {"color": "#D8DCE0"}, {"weight": 0.7}]
  },
  {
    "featureType": "road.local",
    "elementType": "labels",
    "stylers": [{"visibility": "simplified"}]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry",
    "stylers": [{"color": "#FFFFFF"}, {"weight": 2}]
  },
  {
    "featureType": "road.arterial",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#BEC4CA"}, {"weight": 1}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#F8F9FA"}, {"weight": 2.5}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#AEB5BC"}, {"weight": 1.4}]
  },
  {
    "featureType": "transit",
    "stylers": [{"visibility": "off"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#BFDDE8"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#66838C"}]
  }
]
''';

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
          style: _uberInspiredMapStyle,
          buildingsEnabled: true,
          indoorViewEnabled: false,
          initialCameraPosition: CameraPosition(
            target: LatLng(
              mapOPTController.currentLatitudePosition?.value ??
                  defaultLocation.latitude,
              mapOPTController.currentLongitudePosition?.value ??
                  defaultLocation.longitude,
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
