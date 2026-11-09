import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/settings_page.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

import 'helpers/fakes.dart';

Future<AppController> openSettings(
  WidgetTester tester, {
  AppSettings? settings,
  Future<bool> Function()? requestNotifications,
}) async {
  await tester.runAsync(SymbolSheets.load);
  final controller = AppController(
    link: FakeLink(),
    store: MemoryStore(settings ?? const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true)),
  );
  await controller.init();
  await tester.pumpWidget(MaterialApp(home: SettingsPage(controller: controller, requestNotificationPermission: requestNotifications)));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('picking a symbol is applied to the saved settings immediately, without pressing Kaydet',
      (tester) async {
    final controller = await openSettings(tester);
    expect((controller.settings.symbolTable, controller.settings.symbol), ('/', '-'));

    await tester.tap(find.textContaining('Beacon simgesi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bicycle');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('symbol_/b')));
    await tester.pumpAndSettle();

    expect((controller.settings.symbolTable, controller.settings.symbol), ('/', 'b'));
  });

  testWidgets('symbol pick does not save other unsaved form edits', (tester) async {
    final controller = await openSettings(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Beacon yorumu'), 'draft comment');
    await tester.tap(find.textContaining('Beacon simgesi'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bicycle');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('symbol_/b')));
    await tester.pumpAndSettle();
    expect(controller.settings.symbol, 'b');
    expect(controller.settings.comment, isNot('draft comment')); // text fields still need Kaydet
  });

  testWidgets('position source switch is applied immediately', (tester) async {
    final controller = await openSettings(tester);
    expect(controller.settings.positionSource, PositionSource.manual);
    await tester.ensureVisible(find.text('Telefon GPS')); // the sections push it below the first screen
    await tester.pumpAndSettle();
    await tester.tap(find.text('Telefon GPS'));
    await tester.pumpAndSettle();
    expect(controller.settings.positionSource, PositionSource.phone);
  });

  testWidgets('an invalid tile URL is refused on save, a valid one is stored', (tester) async {
    final controller = await openSettings(tester);
    final field = find.widgetWithText(TextField, 'Harita karo adresi');
    await tester.scrollUntilVisible(field, 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(field, 'http://insecure.example.com/{z}/{x}/{y}.png');
    await tester.scrollUntilVisible(find.text('Kaydet'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(controller.settings.tileUrl, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(find.textContaining('Harita karo adresi'), findsWidgets);

    await tester.pump(const Duration(seconds: 6)); // let the error snack bar leave the screen
    await tester.pumpAndSettle();
    await tester.enterText(field, 'https://tiles.example.com/{z}/{x}/{y}.png');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(controller.settings.tileUrl, 'https://tiles.example.com/{z}/{x}/{y}.png');
  });

  group('Android Auto section', () {
    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
    }

    testWidgets('voice reply is off by default and the switch is saved immediately', (tester) async {
      final controller = await openSettings(tester);
      expect(controller.settings.carVoiceReply, isFalse);
      final tile = find.widgetWithText(SwitchListTile, 'Arabadan sesli yanıt');
      await scrollTo(tester, tile);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(controller.settings.carVoiceReply, isTrue);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(controller.settings.carVoiceReply, isFalse);
    });

    testWidgets('the section warns that a spoken reply transmits without a dialog', (tester) async {
      await openSettings(tester);
      final warning = find.textContaining('onay penceresi olmadan');
      await scrollTo(tester, warning);
      expect(warning, findsOneWidget);
    });

    testWidgets('the notification permission button reports the outcome', (tester) async {
      var asked = 0;
      await openSettings(tester, requestNotifications: () async {
        asked++;
        return false;
      });
      final button = find.text('Bildirim iznini kontrol et');
      await scrollTo(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.textContaining('verilmedi'), findsWidgets);
    });
  });
}
