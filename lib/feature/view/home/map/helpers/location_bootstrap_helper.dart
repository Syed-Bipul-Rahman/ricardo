import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

bool isValidLatLng(double? lat, double? lng) {
  if (lat == null || lng == null) return false;
  if (lat.isNaN || lng.isNaN) return false;
  if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return false;
  if (lat.abs() > 90 || lng.abs() > 180) return false;
  return true;
}

bool isUnknownAddressText(String? value) {
  if (value == null) return true;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return true;
  final lower = trimmed.toLowerCase();
  return lower == 'unknown' ||
      lower == 'unnamed road' ||
      lower == 'null' ||
      lower.contains('unknown address') ||
      lower == 'fetching location...' ||
      lower == 'location not available' ||
      lower == 'no address found';
}

/// Cold start: OS last-known is often null until this app gets a GPS fix.
/// Timeouts on [Geolocator.getCurrentPosition] used to abort before GPS warmed,
/// so the map stayed on the default pin and reverse-geocode returned "Unknown".
Future<Position?> resolveInitialPosition() async {
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && isValidLatLng(last.latitude, last.longitude)) {
      return last;
    }
  } catch (e) {
    debugPrint('getLastKnownPosition failed: $e');
  }

  try {
    final current = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 8),
    );
    if (isValidLatLng(current.latitude, current.longitude)) return current;
  } catch (e) {
    debugPrint('getCurrentPosition(medium) failed: $e');
  }

  final streamed = await _firstFixFromStream(
    timeout: const Duration(seconds: 12),
  );
  if (streamed != null) return streamed;

  return null;
}

Future<Position?> _firstFixFromStream({required Duration timeout}) async {
  StreamSubscription<Position>? sub;
  final completer = Completer<Position?>();

  try {
    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen(
      (pos) {
        if (!isValidLatLng(pos.latitude, pos.longitude)) return;
        if (!completer.isCompleted) completer.complete(pos);
      },
      onError: (Object e) {
        debugPrint('position stream bootstrap failed: $e');
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    return await completer.future.timeout(timeout, onTimeout: () => null);
  } catch (e) {
    debugPrint('first stream fix failed: $e');
    return null;
  } finally {
    await sub?.cancel();
  }
}

Future<({String firstLine, String secondLine, String full})?>
    reverseGeocodeAddressParts(double lat, double lng) async {
  if (!isValidLatLng(lat, lng)) return null;

  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final parsed = _partsFromPlacemark(placemarks.first);
        if (parsed != null) return parsed;
      }
    } catch (e) {
      debugPrint('placemarkFromCoordinates attempt $attempt failed: $e');
    }
    await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
  }

  return _googleGeocodeFallback(lat, lng);
}

({String firstLine, String secondLine, String full})? _partsFromPlacemark(
  Placemark place,
) {
  String keep(String? value) {
    if (isUnknownAddressText(value)) return '';
    return value!.trim();
  }

  final firstParts = <String>[
    keep(place.street),
    keep(place.subLocality),
  ].where((e) => e.isNotEmpty).toList();

  final secondParts = <String>[
    keep(place.locality),
    keep(place.subAdministrativeArea),
    keep(place.administrativeArea),
    keep(place.country),
  ].where((e) => e.isNotEmpty).toList();

  // Drop duplicates (e.g. locality repeated as subAdministrativeArea).
  final seen = <String>{};
  final secondUnique = <String>[];
  for (final part in secondParts) {
    final key = part.toLowerCase();
    if (seen.add(key)) secondUnique.add(part);
  }

  if (firstParts.isEmpty && secondUnique.isEmpty) return null;

  final firstLine =
      firstParts.isNotEmpty ? firstParts.join(', ') : secondUnique.first;
  final secondLine = firstParts.isEmpty
      ? secondUnique.skip(1).join(', ')
      : secondUnique.join(', ');
  final full = [firstLine, secondLine].where((e) => e.isNotEmpty).join(', ');
  if (isUnknownAddressText(full)) return null;
  return (firstLine: firstLine, secondLine: secondLine, full: full);
}

Future<({String firstLine, String secondLine, String full})?>
    _googleGeocodeFallback(double lat, double lng) async {
  final apiKey = dotenv.env['MAP_API_KEY'] ?? '';
  if (apiKey.isEmpty) return null;

  try {
    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json'
      '?latlng=$lat,$lng&key=$apiKey',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body);
    if (json is! Map || json['status'] != 'OK') return null;
    final results = json['results'];
    if (results is! List || results.isEmpty) return null;

    final formatted = results.first['formatted_address']?.toString() ?? '';
    if (isUnknownAddressText(formatted)) return null;

    final comma = formatted.indexOf(',');
    if (comma <= 0 || comma >= formatted.length - 1) {
      return (firstLine: formatted, secondLine: '', full: formatted);
    }
    return (
      firstLine: formatted.substring(0, comma).trim(),
      secondLine: formatted.substring(comma + 1).trim(),
      full: formatted,
    );
  } catch (e) {
    debugPrint('Google geocode fallback failed: $e');
    return null;
  }
}
