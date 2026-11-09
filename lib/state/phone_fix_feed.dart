import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'auto_beacon.dart';
import '../l10n/app_strings.dart';

/// Source of phone GPS readings for automatic beacons. An interface so the UI can be tested.
abstract class PhoneFixFeed {
  /// Starts delivering fixes to [onFix]. Returns null on success or a user-facing reason it cannot.
  Future<String?> start(void Function(PhoneFix fix) onFix);

  Future<void> stop();
}

/// [PhoneFixFeed] on top of the Geolocator position stream.
///
/// On Android the stream runs inside a foreground service (type `location`) with an ongoing
/// notification, so readings keep coming with the screen off or another app in front. The service
/// is started while the app is visible (the user taps "start"), which is what Android allows
/// without the separate "all the time" location permission.
class GeolocatorFeed implements PhoneFixFeed {
  GeolocatorFeed({this.notificationTitle = 'TrackBridge', String? notificationText}) : _notificationText = notificationText;

  final String notificationTitle;
  final String? _notificationText;

  /// Resolved when the service starts, so it follows the current interface language.
  String get notificationText => _notificationText ?? t('Otomatik beacon için konum kullanılıyor');
  StreamSubscription<Position>? _sub;

  @visibleForTesting
  static LocationSettings buildSettings({required bool android, required String title, required String text}) {
    if (!android) {
      return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    }
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: title,
        notificationText: text,
        notificationChannelName: 'Konum (otomatik beacon)',
        setOngoing: true,
      ),
    );
  }

  @visibleForTesting
  static PhoneFix toFix(Position p) {
    final heading = p.heading;
    return PhoneFix(
      lat: p.latitude,
      lon: p.longitude,
      speedKmh: p.speed < 0 ? 0 : p.speed * 3.6,
      headingDeg: heading >= 0 && heading <= 360 && p.speed > 0.5 ? heading : null,
      accuracyM: p.accuracy,
      time: p.timestamp,
    );
  }

  @override
  Future<String?> start(void Function(PhoneFix fix) onFix) async {
    await stop();
    if (!await Geolocator.isLocationServiceEnabled()) return t('Telefonun konum servisi kapalı.');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return t('Konum izni verilmedi.');
    }
    final settings = buildSettings(
      android: defaultTargetPlatform == TargetPlatform.android,
      title: notificationTitle,
      text: notificationText,
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((p) => onFix(toFix(p)), onError: (Object _) {});
    return null;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
