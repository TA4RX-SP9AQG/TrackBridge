import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/home_page.dart';
import 'package:trackbridge/ui/map_page.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

import 'helpers/fakes.dart';

Future<void> openHome(WidgetTester tester) async {
  await tester.runAsync(SymbolSheets.load);
  final controller = AppController(
    link: FakeLink(),
    store: MemoryStore(const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true)),
  );
  await controller.init();
  await tester.pumpWidget(MaterialApp(home: HomePage(controller: controller)));
  await tester.pump();
}

void main() {
  testWidgets('has five tabs including the map', (tester) async {
    await openHome(tester);
    for (final label in ['Bağlantı', 'Harita', 'Mesajlar', 'Beacon', 'Ayarlar']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('the map is not built (no tile requests) until its tab is opened', (tester) async {
    await openHome(tester);
    expect(find.byType(MapPage), findsNothing);
    await tester.tap(find.widgetWithText(NavigationDestination, 'Harita'));
    await tester.pump();
    expect(find.byType(MapPage), findsOneWidget);
  });
}
