import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/background/background_service.dart';
import 'package:trackbridge/background/heartbeat.dart';
import 'package:trackbridge/core/time_format.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/app_theme.dart';
import 'package:trackbridge/ui/background_section.dart';

import 'background_test.dart' show FakeBackgroundService, MemoryHeartbeatStore;
import 'helpers/fakes.dart';

class Rig {
  Rig(this.controller, this.heartbeat, this.service, this.fake, this.clock);

  final AppController controller;
  final Heartbeat heartbeat;
  final ServiceSwitchController service;
  final FakeBackgroundService fake;
  DateTime clock;
}

Future<Rig> pumpSection(WidgetTester tester, {FakeBackgroundService? fake, HeartbeatSnapshot? previous}) async {
  final link = FakeLink()..setConnected(true);
  final controller = AppController(link: link, store: MemoryStore(const AppSettings(callsign: 'N0DEMO-9')));
  await controller.init();
  var clock = DateTime(2026, 11, 8, 12);
  final heartbeat = Heartbeat(store: MemoryHeartbeatStore(previous), now: () => clock, interval: const Duration(seconds: 10));
  await heartbeat.start();
  final f = fake ?? FakeBackgroundService();
  final service = ServiceSwitchController(f);
  final rig = Rig(controller, heartbeat, service, f, clock);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: BackgroundSection(controller: controller, tools: BackgroundTools(heartbeat: heartbeat, service: service)),
      ),
    ),
  ));
  await tester.pump();
  rig.clock = clock;
  return rig;
}

void main() {
  testWidgets('shows the heartbeat numbers, uptime and the tracker state', (tester) async {
    final rig = await pumpSection(tester);
    expect(find.text('Arka plan testi'), findsOneWidget);
    expect(find.text('0'), findsWidgets); // no beats yet
    rig.heartbeat.tick();
    rig.heartbeat.tick();
    await tester.pump();
    expect(find.text('2'), findsWidgets);
    expect(find.textContaining('Bağlı'), findsWidgets);
    rig.heartbeat.stop();
  });

  testWidgets('the switch starts the service, and its text explains the persistent notification', (tester) async {
    final rig = await pumpSection(tester);
    expect(find.textContaining('Kalıcı bir bildirim'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(rig.fake.starts, 1);
    expect(rig.service.enabled, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    rig.heartbeat.stop();
  });

  testWidgets('a refused notification permission is explained and the switch stays off', (tester) async {
    final rig = await pumpSection(tester, fake: FakeBackgroundService(result: BackgroundStartResult.permissionDenied));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bildirim izni'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    rig.heartbeat.stop();
  });

  testWidgets('a long gap between beats is flagged as the process having been frozen', (tester) async {
    final rig = await pumpSection(tester);
    rig.heartbeat.tick();
    await tester.pump();
    expect(find.textContaining('dondu'), findsNothing);
    // Move the clock the heartbeat reads: it is captured in the closure of pumpSection, so use a new rig.
    rig.heartbeat.stop();

    var clock = DateTime(2026, 11, 8, 12);
    final heartbeat = Heartbeat(store: MemoryHeartbeatStore(), now: () => clock, interval: const Duration(seconds: 10));
    await heartbeat.start();
    heartbeat.tick();
    clock = clock.add(const Duration(minutes: 4));
    heartbeat.tick();
    final controller = AppController(link: FakeLink(), store: MemoryStore(const AppSettings()));
    await controller.init();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: BackgroundSection(
            controller: controller,
            tools: BackgroundTools(heartbeat: heartbeat, service: ServiceSwitchController(FakeBackgroundService())),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.textContaining('dondu'), findsOneWidget);
    heartbeat.stop();
  });

  testWidgets('the previous process run is shown when there was one', (tester) async {
    final rig = await pumpSection(
      tester,
      previous: HeartbeatSnapshot(count: 42, startedAt: DateTime(2026, 11, 8, 9), lastTick: DateTime(2026, 11, 8, 11, 30), maxGapSeconds: 12),
    );
    expect(find.textContaining('Önceki oturum'), findsOneWidget);
    expect(find.textContaining('42'), findsWidgets);
    rig.heartbeat.stop();
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 5, seconds: 3)), '5:03');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 9)), '1:02:09');
    expect(formatDuration(const Duration(seconds: -4)), '0:00');
  });
}
