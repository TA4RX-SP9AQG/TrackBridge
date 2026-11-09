import 'dart:math' as math;

import '../l10n/app_strings.dart';

/// One GPS reading, reduced to what SmartBeaconing needs.
class SmartFix {
  const SmartFix({required this.speedKmh, required this.time, this.headingDeg});

  final double speedKmh;

  /// 0-360, null when unknown (for example while standing still).
  final double? headingDeg;
  final DateTime time;
}

enum BeaconDecision { none, first, rate, turn }

/// SmartBeaconing parameters (HamHUD). Speeds are in km/h; the turn slope is in
/// degrees x mph, as in the original algorithm.
class SmartBeaconParams {
  const SmartBeaconParams({
    required this.slowSpeedKmh,
    required this.fastSpeedKmh,
    required this.slowRateSeconds,
    required this.fastRateSeconds,
    required this.minTurnTimeSeconds,
    required this.minTurnAngleDeg,
    required this.turnSlope,
  });

  /// Never beacon faster than this, whatever the parameters say (airtime etiquette).
  static const int minRateSeconds = 30;

  static const SmartBeaconParams walking = SmartBeaconParams(
    slowSpeedKmh: 1.5,
    fastSpeedKmh: 8,
    slowRateSeconds: 600,
    fastRateSeconds: 90,
    minTurnTimeSeconds: 30,
    minTurnAngleDeg: 30,
    turnSlope: 255,
  );

  static const SmartBeaconParams bicycle = SmartBeaconParams(
    slowSpeedKmh: 3,
    fastSpeedKmh: 30,
    slowRateSeconds: 600,
    fastRateSeconds: 90,
    minTurnTimeSeconds: 20,
    minTurnAngleDeg: 30,
    turnSlope: 255,
  );

  static const SmartBeaconParams car = SmartBeaconParams(
    slowSpeedKmh: 8,
    fastSpeedKmh: 96,
    slowRateSeconds: 1800,
    fastRateSeconds: 180,
    minTurnTimeSeconds: 15,
    minTurnAngleDeg: 30,
    turnSlope: 255,
  );

  static const Map<String, SmartBeaconParams> presets = {'Yürüyüş': walking, 'Bisiklet': bicycle, 'Araç': car};

  final double slowSpeedKmh;
  final double fastSpeedKmh;
  final int slowRateSeconds;
  final int fastRateSeconds;
  final int minTurnTimeSeconds;
  final double minTurnAngleDeg;
  final double turnSlope;

  /// Throws [ArgumentError] when the values make no sense.
  void validate() {
    if (slowSpeedKmh <= 0 || fastSpeedKmh <= slowSpeedKmh) throw ArgumentError(t('Hızlar: yavaş < hızlı olmalı.'));
    if (fastRateSeconds < minRateSeconds || slowRateSeconds <= fastRateSeconds) {
      throw ArgumentError(t('Aralıklar: hızlı >= {minRateSeconds} sn ve yavaş > hızlı olmalı.', {'minRateSeconds': minRateSeconds}));
    }
  }

  /// Seconds between beacons at [speedKmh]: the slow rate when slow, the fast rate when fast, and
  /// `fast rate x fast speed / speed` in between (clamped to the two rates).
  double rateSecondsFor(double speedKmh) {
    if (speedKmh.isNaN || speedKmh <= slowSpeedKmh) return slowRateSeconds.toDouble();
    if (speedKmh >= fastSpeedKmh) return fastRateSeconds.toDouble();
    final rate = fastRateSeconds * fastSpeedKmh / speedKmh;
    return rate.clamp(fastRateSeconds.toDouble(), slowRateSeconds.toDouble());
  }

  /// Heading change that triggers a corner beacon at [speedKmh].
  double turnThresholdDeg(double speedKmh) {
    final mph = speedKmh / 1.609344;
    return minTurnAngleDeg + turnSlope / mph;
  }
}

/// Decides when a moving station should beacon. Pure logic: feed it fixes, tell it when a beacon
/// was really sent.
class SmartBeaconEngine {
  SmartBeaconEngine(this.params) {
    params.validate();
  }

  final SmartBeaconParams params;

  SmartFix? _last;

  /// Call after a beacon was actually transmitted for [fix].
  void markSent(SmartFix fix) => _last = fix;

  void reset() => _last = null;

  BeaconDecision evaluate(SmartFix fix) {
    final last = _last;
    if (last == null) return BeaconDecision.first;
    final seconds = fix.time.difference(last.time).inMilliseconds / 1000;
    if (seconds >= params.rateSecondsFor(fix.speedKmh)) return BeaconDecision.rate;
    final heading = fix.headingDeg;
    final lastHeading = last.headingDeg;
    if (fix.speedKmh > params.slowSpeedKmh && heading != null && lastHeading != null && seconds > params.minTurnTimeSeconds) {
      if (_angleDiff(heading, lastHeading) > params.turnThresholdDeg(fix.speedKmh)) return BeaconDecision.turn;
    }
    return BeaconDecision.none;
  }

  static double _angleDiff(double a, double b) {
    final d = (a - b).abs() % 360;
    return math.min(d, 360 - d);
  }
}
