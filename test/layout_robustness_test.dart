import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/app_theme.dart';
import 'package:trackbridge/ui/home_page.dart';
import 'package:trackbridge/ui/map_page.dart';
import 'package:trackbridge/ui/messages_page.dart';
import 'package:trackbridge/ui/symbol_picker.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

import 'helpers/fakes.dart';
import 'helpers/test_fonts.dart';

// Small phone, landscape and the largest system text size: no overflow, no exceptions.
// (Checklist items from the UI/UX review: "375px / landscape" and "Dynamic Type".)

const _tabs = ['Bağlantı', 'Harita', 'Mesajlar', 'Beacon', 'Ayarlar'];

Future<AppController> demo() async {
  final link = FakeLink();
  final controller = AppController(
    link: link,
    store: MemoryStore(const AppSettings(
      callsign: 'N0DEMO-9',
      noticeAccepted: true,
      manualLat: 52.2297,
      manualLon: 21.0122,
    )),
    now: () => DateTime(2026, 11, 8, 18, 40),
  );
  await controller.init();
  link.setConnected(true);
  link.receive(frameBytes('N1TEST-7', 'APLOX1', '!5003.88N/01956.70E>088/036A fairly long comment that has to wrap onto more lines',
      path: ['N3NODE-2*']));
  link.receive(frameBytes('N1TEST-7', 'APLOX1', ':N0DEMO-9 :Merhaba, duyuyor musun? Bu biraz uzun bir mesaj metni{12'));
  return controller;
}

Widget app(Widget home, double textScale) => MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

void main() {
  var realFonts = false;
  setUpAll(() async => realFonts = await loadRealFonts());

  for (final size in const [Size(360, 640), Size(640, 360)]) {
    for (final scale in const [1.0, 1.6]) {
      final label = '${size.width.toInt()}x${size.height.toInt()} text x$scale';

      testWidgets('every tab fits at $label', (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK fonts not found; the default test font is too wide to judge layout.');
          return;
        }
        await tester.runAsync(SymbolSheets.load);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final controller = await demo();
        await tester.pumpWidget(app(HomePage(controller: controller), scale));
        await tester.pump();
        await tester.pumpAndSettle();
        for (final tab in _tabs) {
          await tester.tap(find.widgetWithText(NavigationDestination, tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'tab $tab at $label');
        }
      });

      testWidgets('chat, symbol picker and station sheet fit at $label', (tester) async {
        if (!realFonts) {
          markTestSkipped('Flutter SDK fonts not found; the default test font is too wide to judge layout.');
          return;
        }
        await tester.runAsync(SymbolSheets.load);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final controller = await demo();

        await tester.pumpWidget(app(ChatPage(controller: controller, peer: 'N1TEST-7'), scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'chat at $label');

        await tester.pumpWidget(app(const SymbolPickerPage(initialTable: '/', initialCode: '>'), scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'picker at $label');

        await tester.pumpWidget(app(MapPage(controller: controller, tileProvider: EmptyTileProvider()), scale));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'station sheet at $label');
        expect(find.text('Yol tarifi'), findsOneWidget);
      });
    }
  }
}
