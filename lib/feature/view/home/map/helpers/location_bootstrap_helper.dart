import 'package:flutter/foundation.dart';
import 'package:ricardo/feature/view/home/link_export_file.dart';

Future<Position?> resolveInitialPosition() async {
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return last;
  } catch (e) {
    debugPrint('getLastKnownPosition failed: $e');
  }
  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    ).timeout(const Duration(seconds: 6));
  } catch (e) {
    debugPrint('getCurrentPosition(medium) failed: $e');
  }
  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 15));
  } catch (e) {
    debugPrint('getCurrentPosition(high) failed: $e');
  }

  return null;
}
