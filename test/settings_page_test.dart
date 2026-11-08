import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/settings_page.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

import 'helpers/fakes.dart';

Future<AppController> openSettings(WidgetTester tester, {AppSettings? settings}) async {
  await tester.runAsync(SymbolSheets.load);
  final controller = AppController(
    link: FakeLink(),
    store: MemoryStore(settings ?? const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true)),
  );
  await controller.init();
  await tester.pumpWidget(MaterialApp(home: SettingsPage(controller: controller)));
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
    await tester.tap(find.text('Telefon GPS'));
    await tester.pumpAndSettle();
    expect(controller.settings.positionSource, PositionSource.phone);
  });
}
