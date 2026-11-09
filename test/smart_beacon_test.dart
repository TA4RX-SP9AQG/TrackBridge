import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/smart_beacon.dart';

final t0 = DateTime(2026, 11, 9, 10);

SmartFix fix(double speedKmh, {double? heading, int secs = 0}) =>
    SmartFix(speedKmh: speedKmh, headingDeg: heading, time: t0.add(Duration(seconds: secs)));

void main() {
  const car = SmartBeaconParams.car; // slow 8 km/h, fast 96 km/h, slow 1800 s, fast 180 s, turn 30 deg, slope 255, 15 s

  test('the first fix always beacons', () {
    final e = SmartBeaconEngine(car);
    expect(e.evaluate(fix(0)), BeaconDecision.first);
  });

  test('nothing is sent right after a beacon', () {
    final e = SmartBeaconEngine(car)..markSent(fix(50, heading: 90));
    expect(e.evaluate(fix(50, heading: 90, secs: 5)), BeaconDecision.none);
  });

  group('rate by speed (HamHUD)', () {
    test('standing or very slow: only at the slow rate', () {
      final e = SmartBeaconEngine(car)..markSent(fix(0));
      expect(e.evaluate(fix(0, secs: 1799)), BeaconDecision.none);
      expect(e.evaluate(fix(0, secs: 1800)), BeaconDecision.rate);
    });

    test('at or above fast speed: the fast rate', () {
      final e = SmartBeaconEngine(car)..markSent(fix(100));
      expect(e.evaluate(fix(100, secs: 179)), BeaconDecision.none);
      expect(e.evaluate(fix(100, secs: 180)), BeaconDecision.rate);
    });

    test('in between: fast rate x fast speed / speed (48 km/h -> 360 s)', () {
      expect(car.rateSecondsFor(48), closeTo(360, 1e-9));
      final e = SmartBeaconEngine(car)..markSent(fix(48));
      expect(e.evaluate(fix(48, secs: 359)), BeaconDecision.none);
      expect(e.evaluate(fix(48, secs: 360)), BeaconDecision.rate);
    });

    test('the interpolated rate is clamped between fast and slow rate', () {
      expect(car.rateSecondsFor(9), 1800); // 180*96/9 = 1920 -> clamped to the slow rate
      expect(car.rateSecondsFor(500), 180);
      expect(car.rateSecondsFor(-3), 1800); // bad speed values never produce a faster rate
    });
  });

  group('corner pegging', () {
    test('a big turn at speed beacons once the minimum turn time has passed', () {
      final e = SmartBeaconEngine(car)..markSent(fix(60, heading: 90));
      // 60 km/h = 37.3 mph -> threshold 30 + 255/37.3 = 36.8 degrees
      expect(e.evaluate(fix(60, heading: 135, secs: 20)), BeaconDecision.turn);
    });

    test('a small turn does not', () {
      final e = SmartBeaconEngine(car)..markSent(fix(60, heading: 90));
      expect(e.evaluate(fix(60, heading: 110, secs: 20)), BeaconDecision.none);
    });

    test('a turn sooner than the minimum turn time does not', () {
      final e = SmartBeaconEngine(car)..markSent(fix(60, heading: 90));
      expect(e.evaluate(fix(60, heading: 180, secs: 10)), BeaconDecision.none);
    });

    test('the threshold grows at low speed (turn slope)', () {
      final e = SmartBeaconEngine(car)..markSent(fix(15, heading: 0));
      // 15 km/h = 9.3 mph -> 30 + 255/9.3 = 57 degrees; 45 is not enough, 70 is
      expect(e.evaluate(fix(15, heading: 45, secs: 20)), BeaconDecision.none);
      expect(e.evaluate(fix(15, heading: 70, secs: 20)), BeaconDecision.turn);
    });

    test('heading wraps around north', () {
      final e = SmartBeaconEngine(car)..markSent(fix(90, heading: 350));
      expect(e.evaluate(fix(90, heading: 20, secs: 20)), BeaconDecision.none); // 30 degrees
      expect(e.evaluate(fix(90, heading: 60, secs: 20)), BeaconDecision.turn); // 70 degrees
    });

    test('no corner beacons while standing still (noisy heading)', () {
      final e = SmartBeaconEngine(car)..markSent(fix(2, heading: 10));
      expect(e.evaluate(fix(2, heading: 200, secs: 60)), BeaconDecision.none);
    });

    test('an unknown heading never triggers a turn', () {
      final e = SmartBeaconEngine(car)..markSent(fix(60, heading: 90));
      expect(e.evaluate(fix(60, secs: 60)), BeaconDecision.none);
      final e2 = SmartBeaconEngine(car)..markSent(fix(60));
      expect(e2.evaluate(fix(60, heading: 200, secs: 60)), BeaconDecision.none);
    });

    test('the turn is measured against the last transmitted beacon, not the previous fix', () {
      final e = SmartBeaconEngine(car)..markSent(fix(60, heading: 90));
      expect(e.evaluate(fix(60, heading: 110, secs: 20)), BeaconDecision.none);
      expect(e.evaluate(fix(60, heading: 130, secs: 40)), BeaconDecision.turn); // 40 degrees since the beacon
    });
  });

  group('presets', () {
    test('every preset is valid and ordered', () {
      for (final p in SmartBeaconParams.presets.values) {
        expect(p.slowSpeedKmh, lessThan(p.fastSpeedKmh));
        expect(p.fastRateSeconds, lessThan(p.slowRateSeconds));
        expect(p.fastRateSeconds, greaterThanOrEqualTo(SmartBeaconParams.minRateSeconds));
        expect(p.minTurnAngleDeg, greaterThan(0));
      }
    });

    test('walking beacons faster than the car at the same low speed', () {
      expect(SmartBeaconParams.walking.rateSecondsFor(5), lessThan(SmartBeaconParams.car.rateSecondsFor(5)));
    });

    test('invalid parameters are rejected', () {
      expect(
        () => SmartBeaconParams(
          slowSpeedKmh: 50, fastSpeedKmh: 10, slowRateSeconds: 600, fastRateSeconds: 60,
          minTurnTimeSeconds: 15, minTurnAngleDeg: 30, turnSlope: 255,
        ).validate(),
        throwsArgumentError,
      );
      expect(
        () => SmartBeaconParams(
          slowSpeedKmh: 5, fastSpeedKmh: 50, slowRateSeconds: 600, fastRateSeconds: 10,
          minTurnTimeSeconds: 15, minTurnAngleDeg: 30, turnSlope: 255,
        ).validate(),
        throwsArgumentError,
      );
    });
  });
}
