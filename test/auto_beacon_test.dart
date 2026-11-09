import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/smart_beacon.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/auto_beacon.dart';
import 'package:trackbridge/state/models.dart';

import 'helpers/fakes.dart';

late FakeLink link;
late AppController app;
late AutoBeaconController auto;
late DateTime clock;

Future<void> build({
  PositionSource source = PositionSource.manual,
  double? lat = 52.2297,
  double? lon = 21.0122,
  bool connected = true,
  int ambiguity = 2,
}) async {
  link = FakeLink();
  clock = DateTime(2026, 11, 9, 10);
  app = AppController(
    link: link,
    store: MemoryStore(AppSettings(
      callsign: 'N0DEMO-9',
      noticeAccepted: true,
      positionSource: source,
      manualLat: lat,
      manualLon: lon,
      ambiguity: ambiguity,
      comment: '',
    )),
    now: () => clock,
  );
  await app.init();
  if (connected) link.setConnected(true);
  await pump();
  auto = AutoBeaconController(app: app, now: () => clock);
}

PhoneFix gps(double lat, double lon, {double speed = 0, double? heading, double accuracy = 8, int ageSecs = 0}) =>
    PhoneFix(lat: lat, lon: lon, speedKmh: speed, headingDeg: heading, accuracyM: accuracy, time: clock.subtract(Duration(seconds: ageSecs)));

void main() {
  tearDown(() {
    auto.dispose();
    app.dispose();
  });

  group('starting', () {
    test('is off after construction (never persisted as on)', () async {
      await build();
      expect(auto.running, isFalse);
      expect(link.written, isEmpty);
    });

    test('needs a connected tracker', () async {
      await build(connected: false);
      final r = await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 10)));
      expect(r, StartResult.notConnected);
      expect(auto.running, isFalse);
    });

    test('needs a position: fixed mode without coordinates is refused', () async {
      await build(lat: null, lon: null);
      expect(await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 10))), StartResult.noPosition);
    });

    test('the interval must be at least a minute', () async {
      await build();
      expect(await auto.start(AutoBeaconConfig.interval(const Duration(seconds: 30))), StartResult.badConfig);
    });

    test('starting sends the first beacon right away', () async {
      await build();
      expect(await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 10))), StartResult.started);
      expect(auto.running, isTrue);
      expect(link.written, hasLength(1));
      expect(decodeWritten(link.written.single), contains('!5213.  N/02100.  E'));
      expect(auto.log, hasLength(1));
    });
  });

  group('fixed interval', () {
    test('beacons again only after the interval', () async {
      await build();
      await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 5)));
      clock = clock.add(const Duration(minutes: 4, seconds: 59));
      await auto.tick();
      expect(link.written, hasLength(1));
      clock = clock.add(const Duration(seconds: 2));
      await auto.tick();
      expect(link.written, hasLength(2));
    });

    test('stop halts it and nothing more is sent', () async {
      await build();
      await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 1)));
      auto.stop();
      clock = clock.add(const Duration(minutes: 10));
      await auto.tick();
      expect(link.written, hasLength(1));
      expect(auto.running, isFalse);
    });

    test('a dropped tracker connection stops it, and it does not restart on reconnect', () async {
      await build();
      await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 1)));
      link.setConnected(false);
      await pump();
      expect(auto.running, isFalse);
      expect(auto.status, contains('bağlantı'));
      link.setConnected(true);
      await pump();
      clock = clock.add(const Duration(minutes: 5));
      await auto.tick();
      expect(link.written, hasLength(1));
    });

    test('a write failure is reported and does not crash the timer', () async {
      await build();
      await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 1)));
      link.writeError = StateError('GATT');
      clock = clock.add(const Duration(minutes: 2));
      await auto.tick();
      expect(auto.running, isTrue);
      expect(auto.status, contains('gönderilemedi'));
    });
  });

  group('phone GPS', () {
    test('starting needs a fresh fix', () async {
      await build(source: PositionSource.phone);
      expect(await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 5))), StartResult.noPosition);
      auto.onFix(gps(50.08, 19.94, ageSecs: 120));
      expect(await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 5))), StartResult.noPosition);
    });

    test('uses the phone coordinates, truncated by the ambiguity setting', () async {
      await build(source: PositionSource.phone);
      auto.onFix(gps(52.2297, 21.0122));
      await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 5)));
      expect(decodeWritten(link.written.single), contains('!5213.  N/02100.  E'));
    });

    test('a stale or inaccurate fix is skipped, with the reason shown', () async {
      await build(source: PositionSource.phone);
      auto.onFix(gps(52.2297, 21.0122));
      await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 1)));
      clock = clock.add(const Duration(minutes: 2));
      await auto.tick(); // the only fix is now 2 minutes old
      expect(link.written, hasLength(1));
      expect(auto.status, contains('eski'));
      auto.onFix(gps(52.23, 21.01, accuracy: 400));
      await auto.tick();
      expect(link.written, hasLength(1));
      expect(auto.status, contains('hassas'));
      auto.onFix(gps(52.23, 21.01));
      await auto.tick();
      expect(link.written, hasLength(2));
    });
  });

  group('smart mode', () {
    Future<void> startSmart() async {
      await build(source: PositionSource.phone);
      auto.onFix(gps(52.2297, 21.0122, speed: 50, heading: 90));
      await auto.start(AutoBeaconConfig.smart(SmartBeaconParams.car));
    }

    test('standing still sends nothing more until the slow rate', () async {
      await startSmart();
      for (var i = 0; i < 10; i++) {
        clock = clock.add(const Duration(seconds: 30));
        auto.onFix(gps(52.2297, 21.0122, speed: 0));
        await auto.tick();
      }
      expect(link.written, hasLength(1));
    });

    test('a turn at speed sends a beacon (once the 60 s minimum gap has passed)', () async {
      await startSmart();
      clock = clock.add(const Duration(seconds: 65));
      auto.onFix(gps(52.2299, 21.0125, speed: 60, heading: 180));
      await auto.tick();
      expect(link.written, hasLength(2));
    });

    test('never closer than 60 seconds, even when the algorithm asks for it', () async {
      await startSmart();
      clock = clock.add(const Duration(seconds: 20));
      auto.onFix(gps(52.2299, 21.0125, speed: 60, heading: 180)); // a turn, but only 20 s after the last beacon
      await auto.tick();
      expect(link.written, hasLength(1));
      clock = clock.add(const Duration(seconds: 41));
      auto.onFix(gps(52.2301, 21.0127, speed: 60, heading: 180));
      await auto.tick();
      expect(link.written, hasLength(2));
    });

    test('smart mode with fixed position source is refused (nothing moves)', () async {
      await build();
      expect(await auto.start(AutoBeaconConfig.smart(SmartBeaconParams.car)), StartResult.needsPhoneGps);
    });
  });

  test('every automatic beacon is logged, newest first, capped at 20', () async {
    await build();
    await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 1)));
    for (var i = 0; i < 25; i++) {
      clock = clock.add(const Duration(minutes: 2));
      await auto.tick();
    }
    expect(auto.log, hasLength(20));
    expect(auto.log.first.time.isAfter(auto.log.last.time), isTrue);
  });
}
