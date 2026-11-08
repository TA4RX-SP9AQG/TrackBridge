import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/geo.dart';

void main() {
  group('distance and bearing', () {
    test('one degree of longitude on the equator', () {
      expect(distanceKm(0, 0, 0, 1), closeTo(111.195, 0.01));
      expect(bearingDegrees(0, 0, 0, 1), closeTo(90, 1e-6));
      expect(bearingDegrees(0, 0, 1, 0), closeTo(0, 1e-6));
      expect(bearingDegrees(0, 0, 0, -1), closeTo(270, 1e-6));
      expect(bearingDegrees(0, 0, -1, 0), closeTo(180, 1e-6));
    });

    test('Krakow to Warsaw', () {
      expect(distanceKm(50.0647, 19.9450, 52.2297, 21.0122), closeTo(252.0, 0.5));
      expect(bearingDegrees(50.0647, 19.9450, 52.2297, 21.0122), closeTo(16.8, 0.3));
    });

    test('same point is zero distance', () {
      expect(distanceKm(10, 20, 10, 20), 0);
    });
  });

  group('formatting', () {
    test('distance', () {
      expect(formatDistance(0.0), '0 m');
      expect(formatDistance(0.85), '850 m');
      expect(formatDistance(3.44), '3.4 km');
      expect(formatDistance(12.6), '13 km');
      expect(formatDistance(252.1), '252 km');
    });

    test('compass point (Turkish)', () {
      expect(compassPoint(0), 'K');
      expect(compassPoint(359), 'K');
      expect(compassPoint(45), 'KD');
      expect(compassPoint(90), 'D');
      expect(compassPoint(135), 'GD');
      expect(compassPoint(180), 'G');
      expect(compassPoint(225), 'GB');
      expect(compassPoint(270), 'B');
      expect(compassPoint(315), 'KB');
    });

    test('age', () {
      expect(formatAge(const Duration(seconds: 20)), 'az önce');
      expect(formatAge(const Duration(minutes: 5, seconds: 10)), '5 dk önce');
      expect(formatAge(const Duration(hours: 2, minutes: 30)), '2 sa önce');
      expect(formatAge(const Duration(hours: 30)), '1 gün önce');
      expect(formatAge(const Duration(seconds: -5)), 'az önce');
    });
  });
}
