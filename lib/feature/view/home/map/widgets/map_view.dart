import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ricardo/feature/controllers/home/map/map_opt_controller.dart';
import 'package:ricardo/feature/controllers/home/map/ride_controller.dart';
import 'package:ricardo/feature/view/home/map/helpers/location_bootstrap_helper.dart';

/// Google Map host for [MapScreen].
///
/// Rebuilds only when [MapOPTController.liveOverlayRevision] (or discrete
/// ride state) changes — **not** on every LatLng Rx tick. That avoids
/// MapController thrashing and Maps tile REQUEST_TIMEOUT floods while keeping
/// car markers around 30 FPS during motion. The motion engine still chases
/// the latest GPS on vsync; this coalesce only limits GoogleMap rebuilds.
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.mapOPTController,
    required this.currentZoom,
    required this.defaultLocation,
    required this.markersBuilder,
    required this.polylines,
    required this.onMapCreated,
    required this.onCameraMove,
  });

  final MapOPTController mapOPTController;
  final double currentZoom;
  final LatLng defaultLocation;
  final Set<Marker> Function() markersBuilder;
  final Set<Polyline> polylines;
  final void Function(GoogleMapController) onMapCreated;
  final void Function(CameraPosition) onCameraMove;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  Worker? _overlayWorker;
  Timer? _coalesceTimer;
  bool _rebuildQueued = false;

  @override
  void initState() {
    super.initState();
    final rideController = Get.find<RideController>();
    _overlayWorker = everAll(
      [
        widget.mapOPTController.liveOverlayRevision,
        widget.mapOPTController.markerAssetsRevision,
        widget.mapOPTController.rideStatusData,
        widget.mapOPTController.getRideDriverLocation,
        // Passenger "View In Map" — nearby driver markers depend on these.
        rideController.drivers,
        rideController.viewInMapReturn,
      ],
      (_) => _scheduleRebuild(),
    );
  }

  void _scheduleRebuild() {
    if (!mounted || _rebuildQueued) return;
    _rebuildQueued = true;
    _coalesceTimer?.cancel();
    // Coalesce bursts so GoogleMap is not rebuilt faster than ~30 FPS.
    _coalesceTimer = Timer(const Duration(milliseconds: 33), () {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _coalesceTimer?.cancel();
    _overlayWorker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.mapOPTController;
    final lat = c.currentLatitudePosition?.value;
    final lng = c.currentLongitudePosition?.value;
    final LatLng initialTarget = isValidLatLng(lat, lng)
        ? LatLng(lat!, lng!)
        : widget.defaultLocation;

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: initialTarget,
        zoom: widget.currentZoom,
      ),
      onMapCreated: widget.onMapCreated,
      markers: widget.markersBuilder(),
      polylines: widget.polylines,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      onCameraMove: widget.onCameraMove,
    );
  }
}
