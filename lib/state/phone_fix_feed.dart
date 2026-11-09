import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'auto_beacon.dart';

/// Source of phone GPS readings for automatic beacons. An interface so the UI can be tested.
abstract class PhoneFixFeed {
  /// Starts delivering fixes to [onFix]. Returns null on success or a user-facing reason it cannot.
  Future<String?> start(void Function(PhoneFix fix) onFix);

  Future<void> stop();
}

/// [PhoneFixFeed] on top of the Geolocator position stream (foreground use: the app must be open).
class GeolocatorFeed implements PhoneFixFeed {
  StreamSubscription<Position>? _sub;

  @override
  Future<String?> start(void Function(PhoneFix fix) onFix) async {
    await stop();
    if (!await Geolocator.isLocationServiceEnabled()) return 'Telefonun konum servisi kapalı.';
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return 'Konum izni verilmedi.';
    }
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((p) {
      final heading = p.heading;
      onFix(PhoneFix(
        lat: p.latitude,
        lon: p.longitude,
        speedKmh: p.speed < 0 ? 0 : p.speed * 3.6,
        headingDeg: heading >= 0 && heading <= 360 && p.speed > 0.5 ? heading : null,
        accuracyM: p.accuracy,
        time: p.timestamp,
      ));
    }, onError: (Object _) {});
    return null;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
