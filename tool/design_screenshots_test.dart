// Renders the main screens to PNG files so the design can be reviewed without a phone.
//
// Not part of the normal test run (it lives in tool/, not test/). Usage:
//   flutter test tool/design_screenshots_test.dart
// Output folder: environment variable SCREENSHOT_DIR, default build/screens.
// Realistic fonts come from the Flutter SDK (Roboto + Material Icons); the data is fictitious.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/symbols.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/app_theme.dart';
import 'package:trackbridge/ui/home_page.dart';
import 'package:trackbridge/ui/map_page.dart';
import 'package:trackbridge/ui/messages_page.dart';
import 'package:trackbridge/ui/symbol_picker.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

import '../test/helpers/fakes.dart';

final GlobalKey _shot = GlobalKey();

String get _outDir => Platform.environment['SCREENSHOT_DIR'] ?? 'build/screens';

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String name) async => ByteData.sublistView(await File('$dir/$name').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-italic.ttf']) {
    if (File('$dir/$f').existsSync()) roboto.addFont(bytes(f));
  }
  await roboto.load();
  // The test engine has no monospace font; stand in with Roboto so the packet text is readable.
  final mono = FontLoader('monospace')..addFont(bytes('roboto-regular.ttf'));
  await mono.load();
  final icons = FontLoader('MaterialIcons')..addFont(bytes('materialicons-regular.otf'));
  await icons.load();
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<AppController> _demoController({bool connected = true}) async {
  final link = FakeLink();
  final controller = AppController(
    link: link,
    store: MemoryStore(const AppSettings(
      callsign: 'N0DEMO-9',
      noticeAccepted: true,
      manualLat: 52.2297,
      manualLon: 21.0122,
      symbolTable: '/',
      symbol: '>',
      comment: 'TrackBridge',
    )),
    now: () => DateTime(2026, 11, 8, 18, 40),
  );
  await controller.init();
  if (connected) link.setConnected(true);
  for (final f in <List<Object>>[
    ['N1TEST-7', '!5003.88N/01956.70E>088/036Spacer yapiyorum/A=000656'],
    ['N2DEMO-1', '!5421.00N/01839.00E-Ev istasyonu, 144.800'],
    ['N3NODE-2', '!5213.78N/02100.73E#Digipeater WIDE1'],
    ['N1TEST-7', ':N0DEMO-9 :Merhaba, duyuyor musun?{12'],
    ['N4HIKE-9', ':N0DEMO-9 :Tepeden selamlar{3'],
  ]) {
    link.receive(frameBytes(f[0] as String, 'APLOX1', f[1] as String, path: const ['N3NODE-2*']));
  }
  return controller;
}

Widget _app(Widget home, Brightness b) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: home,
      builder: (context, child) => RepaintBoundary(key: _shot, child: child),
    );

void _phone(WidgetTester tester, {double height = 844}) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = Size(390 * 3, height * 3);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
  // Asset images decode on a real isolate; give them time, then draw the final frame.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    // Touch devices show no keyboard focus ring; the desktop test default would draw one.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final tag = brightness == Brightness.dark ? 'dark' : 'light';

    Future<AppController> openHome(WidgetTester tester, {String? tab}) async {
      await tester.runAsync(SymbolSheets.load);
      final controller = await _demoController();
      await tester.pumpWidget(_app(HomePage(controller: controller), brightness));
      await _settle(tester);
      if (tab != null) {
        await tester.tap(find.widgetWithText(NavigationDestination, tab));
        await _settle(tester);
      }
      return controller;
    }

    testWidgets('connect $tag', (tester) async {
      _phone(tester);
      await openHome(tester);
      await _save(tester, '01_connect_$tag');
    });

    testWidgets('messages $tag', (tester) async {
      _phone(tester);
      await openHome(tester, tab: 'Mesajlar');
      await _save(tester, '02_messages_$tag');
    });

    testWidgets('chat $tag', (tester) async {
      _phone(tester);
      await tester.runAsync(SymbolSheets.load);
      final controller = await _demoController();
      final packet = controller.buildMessagePacket(to: 'N1TEST-7', text: 'Duyuyorum, 5/9. Sen nerelerdesin?');
      await controller.transmit(packet);
      await tester.pumpWidget(_app(ChatPage(controller: controller, peer: 'N1TEST-7'), brightness));
      await _settle(tester);
      await _save(tester, '03_chat_$tag');
    });

    testWidgets('beacon $tag', (tester) async {
      _phone(tester);
      await openHome(tester, tab: 'Beacon');
      await _save(tester, '04_beacon_$tag');
    });

    testWidgets('settings $tag', (tester) async {
      _phone(tester, height: 1500);
      await openHome(tester, tab: 'Ayarlar');
      await _save(tester, '05_settings_$tag');
    });

    testWidgets('map $tag', (tester) async {
      _phone(tester);
      await tester.runAsync(SymbolSheets.load);
      final controller = await _demoController();
      await tester.pumpWidget(_app(MapPage(controller: controller, tileProvider: EmptyTileProvider()), brightness));
      await _settle(tester);
      await _save(tester, '06_map_$tag');
    });

    testWidgets('map sheet $tag', (tester) async {
      _phone(tester);
      await tester.runAsync(SymbolSheets.load);
      final controller = await _demoController();
      await tester.pumpWidget(_app(MapPage(controller: controller, tileProvider: EmptyTileProvider()), brightness));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
      await _settle(tester);
      await _save(tester, '07_map_sheet_$tag');
    });

    testWidgets('symbol picker $tag', (tester) async {
      _phone(tester);
      await tester.runAsync(SymbolSheets.load);
      await tester.pumpWidget(_app(const SymbolPickerPage(initialTable: '/', initialCode: '>'), brightness));
      await _settle(tester);
      await _save(tester, '08_symbols_$tag');
    });

    testWidgets('disconnected $tag', (tester) async {
      _phone(tester);
      await tester.runAsync(SymbolSheets.load);
      final controller = await _demoController(connected: false);
      await tester.pumpWidget(_app(HomePage(controller: controller), brightness));
      await _settle(tester);
      await _save(tester, '09_disconnected_$tag');
    });
  }

  // Keep the catalog import used (guards against accidental removal of the symbol layer in this tool).
  test('catalog is available', () => expect(primarySymbols, isNotEmpty));
}
