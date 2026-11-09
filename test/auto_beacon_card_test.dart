import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/auto_beacon.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/state/phone_fix_feed.dart';
import 'package:trackbridge/ui/app_theme.dart';
import 'package:trackbridge/ui/auto_beacon_card.dart';

import 'helpers/fakes.dart';

class FakeFeed implements PhoneFixFeed {
  int starts = 0;
  int stops = 0;
  String? problem;

  @override
  Future<String?> start(void Function(PhoneFix fix) onFix) async {
    starts++;
    return problem;
  }

  @override
  Future<void> stop() async => stops++;
}

const String startLabel = "Otomatik beacon'ı başlat";

Future<(AppController, AutoBeaconController, FakeLink, FakeFeed)> pumpCard(WidgetTester tester, {bool connected = true}) async {
  final link = FakeLink();
  final app = AppController(
    link: link,
    store: MemoryStore(const AppSettings(callsign: 'N0DEMO-9', noticeAccepted: true, manualLat: 52.2297, manualLon: 21.0122)),
  );
  await app.init();
  if (connected) link.setConnected(true);
  final auto = AutoBeaconController(app: app);
  final feed = FakeFeed();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: AutoBeaconCard(controller: app, auto: auto, feed: feed))),
  ));
  await tester.pump();
  return (app, auto, link, feed);
}

void main() {
  testWidgets('starts off, and the start button needs a connected tracker', (tester) async {
    final (_, auto, _, _) = await pumpCard(tester, connected: false);
    expect(auto.running, isFalse);
    expect(find.text('Kapalı'), findsWidgets);
    final button = tester.widget<FilledButton>(find.ancestor(of: find.text(startLabel), matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('starting asks for confirmation and shows what will be public', (tester) async {
    final (_, auto, link, _) = await pumpCard(tester);
    await tester.tap(find.text(startLabel));
    await tester.pumpAndSettle();
    expect(find.text('Otomatik beacon başlatılsın mı?'), findsOneWidget);
    expect(find.textContaining('herkese açık'), findsOneWidget);
    expect(link.written, isEmpty); // nothing before the user confirms
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(auto.running, isFalse);
    expect(link.written, isEmpty);
  });

  testWidgets('confirming starts it and sends the first beacon, stop turns it off', (tester) async {
    final (_, auto, link, _) = await pumpCard(tester);
    await tester.tap(find.text(startLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başlat'));
    await tester.pumpAndSettle();
    expect(auto.running, isTrue);
    expect(link.written, hasLength(1));
    expect(find.text('Durdur'), findsOneWidget);
    await tester.tap(find.text('Durdur'));
    await tester.pumpAndSettle();
    expect(auto.running, isFalse);
  });

  testWidgets('exact precision gets an explicit warning in the confirmation', (tester) async {
    final (app, _, _, _) = await pumpCard(tester);
    await app.updateSettings(app.settings.copyWith(ambiguity: 0));
    await tester.pump();
    await tester.tap(find.text(startLabel));
    await tester.pumpAndSettle();
    expect(find.textContaining('tam konumunuz yayınlanır'), findsOneWidget);
  });

  testWidgets('smart mode with a fixed position source is explained, not started', (tester) async {
    final (_, auto, link, _) = await pumpCard(tester);
    await tester.tap(find.text('Akıllı'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(startLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başlat'));
    await tester.pumpAndSettle();
    expect(auto.running, isFalse);
    expect(link.written, isEmpty);
    expect(find.textContaining('Telefon GPS'), findsWidgets);
  });
}
