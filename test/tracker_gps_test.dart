import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackbridge/core/smart_beacon.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/auto_beacon.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/state/settings_store.dart';

import 'helpers/fakes.dart';

// The tracker's own GPS: the firmware also sends its own beacons to the phone, so the newest one is the
// tracker's position. It is used as the position source of beacons built by the app.

const _tracker = 'SP9TRK-7';
const _beacon = '!5003.88N/01956.70E>';

class Rig {
  Rig(this.link, this.controller, this.clock);
  final FakeLink link;
  final AppController controller;
  final TestClock clock;
}

class TestClock {
  DateTime now = DateTime(2026, 11, 9, 12, 0);
}

Future<Rig> rig({
  PositionSource source = PositionSource.tracker,
  String trackerCallsign = _tracker,
  String callsign = 'SP9AQG-9',
  int ambiguity = 0,
}) async {
  final link = FakeLink();
  final clock = TestClock();
  final controller = AppController(
    link: link,
    store: MemoryStore(AppSettings(
      callsign: callsign,
      trackerCallsign: trackerCallsign,
      noticeAccepted: true,
      positionSource: source,
      ambiguity: ambiguity,
      comment: 'hi',
    )),
    now: () => clock.now,
  );
  await controller.init();
  link.setConnected(true);
  await Future<void>.delayed(Duration.zero);
  return Rig(link, controller, clock);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('a beacon is built from the position of the tracker\'s own beacon', () async {
    final r = await rig();
    r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon, path: ['WIDE1-1']));
    await settle();
    final p = await r.controller.buildBeaconPacket();
    expect(p.tnc2, contains('!5003.88N/01956.70E-hi'));
  });

  test('the newest tracker beacon wins', () async {
    final r = await rig();
    r.link.receive(frameBytes(_tracker, 'APLRT1', '!5003.88N/01956.70E>'));
    await settle();
    r.clock.now = r.clock.now.add(const Duration(minutes: 1));
    r.link.receive(frameBytes(_tracker, 'APLRT1', '!5010.00N/02000.00E>'));
    await settle();
    expect((await r.controller.buildBeaconPacket()).tnc2, contains('!5010.00N/02000.00E-hi'));
  });

  test('the position source is applied: ambiguity still hides digits', () async {
    final r = await rig(ambiguity: 2);
    r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
    await settle();
    expect((await r.controller.buildBeaconPacket()).tnc2, contains('!5003.  N/01956.  E-hi'));
  });

  test('without a tracker callsign the app callsign identifies the tracker', () async {
    final r = await rig(trackerCallsign: '', callsign: 'SP9AQG-9');
    r.link.receive(frameBytes('SP9AQG-9', 'APLRT1', _beacon));
    await settle();
    expect((await r.controller.buildBeaconPacket()).tnc2, contains('!5003.88N/01956.70E-hi'));
  });

  test('other stations are not the tracker', () async {
    final r = await rig();
    r.link.receive(frameBytes('N1TEST-7', 'APLRT1', _beacon));
    await settle();
    expect(r.controller.trackerFix, isNull);
    expect(r.controller.buildBeaconPacket(), throwsA(isA<FormatException>()));
  });

  test('a copy repeated by a digipeater is not the tracker\'s own GPS', () async {
    final r = await rig();
    r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon, path: ['SP9DIG-1*']));
    await settle();
    expect(r.controller.trackerFix, isNull);
  });

  test('a stale tracker position is refused with a clear message', () async {
    final r = await rig();
    r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
    await settle();
    r.clock.now = r.clock.now.add(AppController.maxTrackerFixAge + const Duration(seconds: 1));
    expect(r.controller.freshTrackerPoint, isNull);
    await expectLater(
      r.controller.buildBeaconPacket(),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Tracker'))),
    );
  });

  test('no tracker beacon heard yet: refused, nothing is built', () async {
    final r = await rig();
    await expectLater(r.controller.buildBeaconPacket(), throwsA(isA<FormatException>()));
    expect(r.link.written, isEmpty);
  });

  test('the tracker position is forgotten when the connection drops', () async {
    final r = await rig();
    r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
    await settle();
    expect(r.controller.trackerFix, isNotNull);
    r.link.setConnected(false);
    await settle();
    expect(r.controller.trackerFix, isNull);
  });

  test('objects sent by the tracker are not its position', () async {
    final r = await rig();
    r.link.receive(frameBytes(_tracker, 'APLRT1', ';OBJECT   *092345z5003.88N/01956.70E>'));
    await settle();
    expect(r.controller.trackerFix, isNull);
  });

  test('the map uses the tracker position as "my position" with the tracker source', () async {
    final r = await rig();
    expect(r.controller.ownPosition, isNull);
    r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
    await settle();
    expect(r.controller.ownPosition!.lat, closeTo(50.0647, 0.001));
  });

  test('the other sources are not affected by tracker beacons', () async {
    final r = await rig(source: PositionSource.manual);
    r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
    await settle();
    expect(r.controller.ownPosition, isNull);
    await expectLater(r.controller.buildBeaconPacket(), throwsA(isA<FormatException>()));
  });

  group('automatic beacon with the tracker position', () {
    test('interval mode starts once the tracker has a position, and transmits it', () async {
      final r = await rig();
      final auto = AutoBeaconController(app: r.controller, now: () => r.clock.now);
      expect(await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 5))), StartResult.noPosition);
      r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
      await settle();
      expect(await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 5))), StartResult.started);
      expect(r.link.written, hasLength(1));
      expect(decodeWritten(r.link.written.single), contains('!5003.88N/01956.70E-hi'));
      auto.stop();
    });

    test('a stale tracker position pauses the beacon instead of repeating an old place', () async {
      final r = await rig();
      final auto = AutoBeaconController(app: r.controller, now: () => r.clock.now);
      r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
      await settle();
      await auto.start(AutoBeaconConfig.interval(const Duration(minutes: 1)));
      r.clock.now = r.clock.now.add(AppController.maxTrackerFixAge + const Duration(minutes: 2));
      await auto.tick();
      expect(r.link.written, hasLength(1)); // only the first one
      expect(auto.status, isNot(contains('Son beacon gönderildi')));
      auto.stop();
    });

    test('smart mode needs motion from the phone, not the tracker beacons', () async {
      final r = await rig();
      final auto = AutoBeaconController(app: r.controller, now: () => r.clock.now);
      r.link.receive(frameBytes(_tracker, 'APLRT1', _beacon));
      await settle();
      expect(await auto.start(AutoBeaconConfig.smart(SmartBeaconParams.car)), StartResult.needsPhoneGps);
    });
  });

  test('the tracker callsign and the tracker source are stored', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsSettingsStore();
    await store.save(const AppSettings(positionSource: PositionSource.tracker, trackerCallsign: 'SP9TRK-7'));
    final loaded = await store.load();
    expect(loaded.positionSource, PositionSource.tracker);
    expect(loaded.trackerCallsign, 'SP9TRK-7');
  });
}
