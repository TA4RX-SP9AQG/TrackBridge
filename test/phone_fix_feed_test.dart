import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trackbridge/state/phone_fix_feed.dart';

void main() {
  group('location settings', () {
    test('on Android the feed runs as a foreground service with an ongoing notification', () {
      final s = GeolocatorFeed.buildSettings(android: true, title: 'TrackBridge', text: 'Konum kullanılıyor');
      expect(s, isA<AndroidSettings>());
      final a = s as AndroidSettings;
      final n = a.foregroundNotificationConfig!;
      expect(n.notificationTitle, 'TrackBridge');
      expect(n.notificationText, 'Konum kullanılıyor');
      expect(n.setOngoing, isTrue);
      expect(a.accuracy, LocationAccuracy.high);
      expect(a.distanceFilter, 5);
    });

    test('elsewhere the plain settings are used', () {
      final s = GeolocatorFeed.buildSettings(android: false, title: 't', text: 'x');
      expect(s, isNot(isA<AndroidSettings>()));
      expect(s.accuracy, LocationAccuracy.high);
    });
  });

  group('fix conversion', () {
    Position pos({double speed = 10, double heading = 90, double accuracy = 5}) => Position(
          latitude: 52.2,
          longitude: 21.0,
          timestamp: DateTime(2026, 11, 9, 10),
          accuracy: accuracy,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: heading,
          headingAccuracy: 0,
          speed: speed,
          speedAccuracy: 0,
        );

    test('speed is converted from m/s to km/h', () {
      expect(GeolocatorFeed.toFix(pos(speed: 10)).speedKmh, closeTo(36, 1e-9));
    });

    test('negative or unknown speed is treated as standing still', () {
      expect(GeolocatorFeed.toFix(pos(speed: -1)).speedKmh, 0);
    });

    test('heading is dropped while standing still or when invalid', () {
      expect(GeolocatorFeed.toFix(pos(speed: 0.2, heading: 120)).headingDeg, isNull);
      expect(GeolocatorFeed.toFix(pos(speed: 5, heading: -1)).headingDeg, isNull);
      expect(GeolocatorFeed.toFix(pos(speed: 5, heading: 120)).headingDeg, 120);
    });

    test('position, accuracy and time are carried over', () {
      final f = GeolocatorFeed.toFix(pos(accuracy: 12));
      expect((f.lat, f.lon, f.accuracyM), (52.2, 21.0, 12));
      expect(f.time, DateTime(2026, 11, 9, 10));
    });
  });
}
