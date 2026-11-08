import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/background/background_coordinator.dart';
import 'package:trackbridge/background/background_service.dart';
import 'package:trackbridge/background/heartbeat.dart';

import 'helpers/fakes.dart';

class MemoryHeartbeatStore implements HeartbeatStore {
  MemoryHeartbeatStore([this.stored]);

  HeartbeatSnapshot? stored;
  int saves = 0;

  @override
  Future<HeartbeatSnapshot?> load() async => stored;

  @override
  Future<void> save(HeartbeatSnapshot snapshot) async {
    stored = snapshot;
    saves++;
  }
}

class FakeBackgroundService implements BackgroundService {
  FakeBackgroundService({this.result = BackgroundStartResult.started});

  BackgroundStartResult result;
  bool running = false;
  int starts = 0;
  int stops = 0;
  String? lastBody;

  @override
  bool get isRunning => running;

  @override
  Future<BackgroundStartResult> start({required String title, required String body}) async {
    starts++;
    lastBody = body;
    if (result == BackgroundStartResult.started) running = true;
    return result;
  }

  @override
  Future<void> update({required String title, required String body}) async => lastBody = body;

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }
}

void main() {
  group('Heartbeat', () {
    late DateTime clock;
    late MemoryHeartbeatStore store;

    Heartbeat build({HeartbeatSnapshot? previous}) {
      clock = DateTime(2026, 11, 8, 12);
      store = MemoryHeartbeatStore(previous);
      return Heartbeat(store: store, now: () => clock, interval: const Duration(seconds: 10));
    }

    test('starts with nothing counted', () {
      final hb = build();
      expect(hb.snapshot.count, 0);
      expect(hb.snapshot.lastTick, isNull);
      expect(hb.running, isFalse);
    });

    test('manual ticks count, record the last time and the largest gap', () async {
      final hb = build();
      await hb.start();
      hb.tick();
      clock = clock.add(const Duration(seconds: 10));
      hb.tick();
      clock = clock.add(const Duration(seconds: 95)); // the process was frozen for a while
      hb.tick();
      clock = clock.add(const Duration(seconds: 10));
      hb.tick();
      expect(hb.snapshot.count, 4);
      expect(hb.snapshot.lastTick, clock);
      expect(hb.snapshot.maxGapSeconds, 95);
      hb.stop();
    });

    test('uptime is measured from start', () async {
      final hb = build();
      await hb.start();
      clock = clock.add(const Duration(minutes: 5, seconds: 3));
      expect(hb.uptime, const Duration(minutes: 5, seconds: 3));
      hb.stop();
    });

    test('every tick is saved so a dead process can be diagnosed later', () async {
      final hb = build();
      await hb.start();
      hb.tick();
      hb.tick();
      await Future<void>.delayed(Duration.zero);
      expect(store.saves, 2);
      expect(store.stored!.count, 2);
      hb.stop();
    });

    test('the run before this process is offered as previousRun and is not mixed into the count', () async {
      final previous = HeartbeatSnapshot(
        count: 42,
        startedAt: DateTime(2026, 11, 8, 9),
        lastTick: DateTime(2026, 11, 8, 11, 30),
        maxGapSeconds: 12,
      );
      final hb = build(previous: previous);
      await hb.start();
      expect(hb.previousRun?.count, 42);
      expect(hb.snapshot.count, 0);
      hb.stop();
    });

    test('starting twice does not double the rate', () async {
      final hb = build();
      await hb.start();
      await hb.start();
      hb.tick();
      expect(hb.snapshot.count, 1);
      hb.stop();
    });

    testWidgets('the timer ticks on its own and stops when told to', (tester) async {
      final hb = build();
      await hb.start();
      await tester.pump(const Duration(seconds: 35));
      expect(hb.snapshot.count, 3);
      hb.stop();
      await tester.pump(const Duration(seconds: 60));
      expect(hb.snapshot.count, 3);
    });

    test('listeners are told about each tick', () async {
      final hb = build();
      var notified = 0;
      hb.addListener(() => notified++);
      await hb.start();
      hb.tick();
      expect(notified, greaterThan(0));
      hb.stop();
    });
  });

  group('ServiceSwitchController', () {
    test('enabling starts the service and reports running', () async {
      final service = FakeBackgroundService();
      final c = ServiceSwitchController(service);
      await c.setEnabled(true, title: 'TrackBridge', body: 'çalışıyor');
      expect(c.enabled, isTrue);
      expect(service.starts, 1);
      expect(c.error, isNull);
    });

    test('a denied notification permission leaves it off and explains why', () async {
      final c = ServiceSwitchController(FakeBackgroundService(result: BackgroundStartResult.permissionDenied));
      await c.setEnabled(true, title: 't', body: 'b');
      expect(c.enabled, isFalse);
      expect(c.error, contains('Bildirim izni'));
    });

    test('missing Bluetooth permission stops it before the service is even started', () async {
      final service = FakeBackgroundService();
      final c = ServiceSwitchController(service, preflight: () async => false);
      await c.setEnabled(true, title: 't', body: 'b');
      expect(c.enabled, isFalse);
      expect(service.starts, 0);
      expect(c.error, contains('Bluetooth izni'));
    });

    test('a granted preflight lets the service start', () async {
      final service = FakeBackgroundService();
      final c = ServiceSwitchController(service, preflight: () async => true);
      await c.setEnabled(true, title: 't', body: 'b');
      expect(c.enabled, isTrue);
      expect(service.starts, 1);
    });

    test('a failed start leaves it off and explains why', () async {
      final c = ServiceSwitchController(FakeBackgroundService(result: BackgroundStartResult.failed));
      await c.setEnabled(true, title: 't', body: 'b');
      expect(c.enabled, isFalse);
      expect(c.error, isNotNull);
    });

    test('disabling stops the service and clears the error', () async {
      final service = FakeBackgroundService();
      final c = ServiceSwitchController(service);
      await c.setEnabled(true, title: 't', body: 'b');
      await c.setEnabled(false, title: 't', body: 'b');
      expect(c.enabled, isFalse);
      expect(service.stops, 1);
      expect(service.running, isFalse);
    });

    test('a second request while one is in flight is ignored', () async {
      final c = ServiceSwitchController(FakeBackgroundService());
      final first = c.setEnabled(true, title: 't', body: 'b');
      final second = c.setEnabled(true, title: 't', body: 'b');
      await Future.wait([first, second]);
      expect((c.service as FakeBackgroundService).starts, 1);
    });

    test('updateBody changes the notification text only while running', () async {
      final service = FakeBackgroundService();
      final c = ServiceSwitchController(service);
      await c.updateBody(title: 't', body: 'ignored');
      expect(service.lastBody, isNull);
      await c.setEnabled(true, title: 't', body: 'first');
      await c.updateBody(title: 't', body: 'second');
      expect(service.lastBody, 'second');
    });
  });

  group('BackgroundCoordinator', () {
    test('when the app is closed with background mode OFF the tracker is disconnected', () async {
      final link = FakeLink()..setConnected(true);
      final c = ServiceSwitchController(FakeBackgroundService());
      final coordinator = BackgroundCoordinator(link: link, service: c);
      await coordinator.handleLifecycle(AppLifecycleState.detached);
      expect(link.info.isConnected, isFalse);
    });

    test('with background mode ON the connection survives the app being closed', () async {
      final link = FakeLink()..setConnected(true);
      final c = ServiceSwitchController(FakeBackgroundService());
      await c.setEnabled(true, title: 't', body: 'b');
      final coordinator = BackgroundCoordinator(link: link, service: c);
      await coordinator.handleLifecycle(AppLifecycleState.detached);
      expect(link.info.isConnected, isTrue);
    });

    test('going to the background (paused/hidden/inactive) never disconnects', () async {
      final link = FakeLink()..setConnected(true);
      final coordinator = BackgroundCoordinator(link: link, service: ServiceSwitchController(FakeBackgroundService()));
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused, AppLifecycleState.resumed]) {
        await coordinator.handleLifecycle(s);
      }
      expect(link.info.isConnected, isTrue);
    });
  });
}
