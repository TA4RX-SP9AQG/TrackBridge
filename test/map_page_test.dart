import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/ui/map_page.dart';
import 'package:trackbridge/ui/symbol_widget.dart';

import 'helpers/fakes.dart';

class MapTestSetup {
  MapTestSetup(this.controller, this.link, this.launcher);

  final AppController controller;
  final FakeLink link;
  final FakeLauncher launcher;
}

Future<MapTestSetup> openMap(
  WidgetTester tester, {
  AppSettings? settings,
  FakeLauncher? launcher,
  MapController? mapController,
}) async {
  await tester.runAsync(SymbolSheets.load);
  final link = FakeLink();
  final controller = AppController(
    link: link,
    store: MemoryStore(settings ??
        const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true, manualLat: 52.2297, manualLon: 21.0122)),
    now: () => DateTime(2026, 11, 8, 12),
  );
  await controller.init();
  link.setConnected(true);
  final l = launcher ?? FakeLauncher(accepts: {'google.navigation', 'geo', 'https'});
  await tester.pumpWidget(MaterialApp(
    home: MapPage(
      controller: controller,
      launcher: l,
      mapController: mapController,
      tileProvider: EmptyTileProvider(),
      now: () => DateTime(2026, 11, 8, 12, 5),
    ),
  ));
  await tester.pump();
  return MapTestSetup(controller, link, l);
}

Future<void> hear(WidgetTester tester, MapTestSetup s, String call, String info, {List<String> path = const []}) async {
  s.link.receive(frameBytes(call, 'APLOX1', info, path: path));
  await tester.pump();
  // The first heard station triggers an automatic "fit all" on the next frame, and flutter_map only
  // draws markers inside the visible area, so wait for the camera to settle before looking for them.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state explains that only RF-heard positions are shown', (tester) async {
    await openMap(tester);
    expect(find.textContaining('Henüz konumlu paket duyulmadı'), findsOneWidget);
  });

  testWidgets('a heard position gets a marker labelled with the callsign', (tester) async {
    final s = await openMap(tester);
    await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>Spacer yapiyorum');
    expect(find.byKey(const ValueKey('station_stn/N1TEST-7')), findsOneWidget);
    expect(find.text('N1TEST-7'), findsWidgets);
    expect(find.textContaining('Henüz konumlu paket duyulmadı'), findsNothing);
  });

  testWidgets('tapping a marker shows the comment, details and distance from our position', (tester) async {
    final s = await openMap(tester);
    await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>088/036Spacer yapiyorum/A=000656',
        path: ['SP9KKK-2*']);
    await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
    await tester.pumpAndSettle();

    expect(find.text('Spacer yapiyorum'), findsOneWidget); // full comment, extensions stripped
    expect(find.textContaining('Car'), findsWidgets); // symbol name
    expect(find.textContaining('50.06467'), findsOneWidget); // position
    expect(find.textContaining('66.7 km/s'), findsOneWidget); // 36 kn
    expect(find.textContaining('88°'), findsOneWidget); // course
    expect(find.textContaining('200 m'), findsOneWidget); // 656 ft altitude
    expect(find.textContaining('252 km'), findsOneWidget); // from our manual position
    expect(find.textContaining('SP9KKK-2*'), findsOneWidget); // via digipeater
    expect(find.textContaining('5 dk önce'), findsOneWidget);
    expect(find.text('Yol tarifi'), findsOneWidget);
    expect(find.text('Mesaj gönder'), findsOneWidget);
  });

  testWidgets('a position without a comment says so', (tester) async {
    final s = await openMap(tester);
    await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>');
    await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
    await tester.pumpAndSettle();
    expect(find.text('Yorum yok'), findsOneWidget);
  });

  testWidgets('"Yol tarifi" starts navigation to the station', (tester) async {
    final s = await openMap(tester);
    await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>x');
    await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yol tarifi'));
    await tester.pumpAndSettle();
    expect(s.launcher.tried, hasLength(1));
    expect(s.launcher.tried.single.scheme, 'google.navigation');
    expect(s.launcher.tried.single.toString(), contains('50.064667,19.945000'));
  });

  testWidgets('when no navigation app can open it the user is told', (tester) async {
    final s = await openMap(tester, launcher: FakeLauncher());
    await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>x');
    await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yol tarifi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('açılamadı'), findsOneWidget);
  });

  testWidgets('"Başka uygulamada aç" uses the map chooser', (tester) async {
    final s = await openMap(tester);
    await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>x');
    await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Başka uygulamada aç'));
    await tester.pumpAndSettle();
    expect(s.launcher.tried.single.scheme, 'geo');
  });

  testWidgets('an object is shown under its name and mentions its owner', (tester) async {
    final s = await openMap(tester);
    await hear(tester, s, 'N1TEST-7', ';LEADER   *092345z4903.50N/07201.75W>');
    await tester.tap(find.byKey(const ValueKey('station_obj/LEADER')));
    await tester.pumpAndSettle();
    expect(find.text('LEADER'), findsWidgets);
    expect(find.textContaining('N1TEST-7'), findsWidgets);
    expect(find.textContaining('nesne'), findsOneWidget);
  });

  testWidgets('without our own position no distance row is shown', (tester) async {
    final s = await openMap(tester, settings: const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true));
    await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>x');
    await tester.tap(find.byKey(const ValueKey('station_stn/N1TEST-7')));
    await tester.pumpAndSettle();
    expect(find.text('Mesafe'), findsNothing);
  });

  testWidgets('attribution names OpenStreetMap for the default tile URL', (tester) async {
    await openMap(tester);
    expect(find.textContaining('OpenStreetMap'), findsWidgets);
  });

  group('"Tümünü göster" button', () {
    bool contains(MapController c, double lat, double lon) => c.camera.visibleBounds.contains(LatLng(lat, lon));

    testWidgets('brings every station and our own position back into view after the map was moved', (tester) async {
      final ctl = MapController();
      final s = await openMap(tester, mapController: ctl);
      await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>'); // near Krakow
      await hear(tester, s, 'N1TEST-8', '!5421.00N/01839.00E>'); // near Gdansk
      await tester.pumpAndSettle();

      ctl.move(const LatLng(0, 0), 3); // user wandered off
      await tester.pumpAndSettle();
      expect(contains(ctl, 50.06, 19.94), isFalse);

      await tester.tap(find.byTooltip('Tümünü göster'));
      await tester.pumpAndSettle();

      expect(contains(ctl, 50.0647, 19.945), isTrue, reason: 'Krakow station');
      expect(contains(ctl, 54.35, 18.65), isTrue, reason: 'Gdansk station');
      expect(contains(ctl, 52.2297, 21.0122), isTrue, reason: 'own position');
    });

    testWidgets('works with a single station and no own position', (tester) async {
      final ctl = MapController();
      final s = await openMap(tester,
          mapController: ctl, settings: const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true));
      await hear(tester, s, 'N1TEST-7', '!5003.88N/01956.70E>');
      await tester.pumpAndSettle();
      ctl.move(const LatLng(0, 0), 3);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tümünü göster'));
      await tester.pumpAndSettle();
      expect(contains(ctl, 50.0647, 19.945), isTrue);
      expect(ctl.camera.zoom, greaterThan(5));
    });

    testWidgets('with nothing to show it leaves the map alone', (tester) async {
      final ctl = MapController();
      await openMap(tester, mapController: ctl, settings: const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true));
      ctl.move(const LatLng(10, 10), 5);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Tümünü göster'));
      await tester.pumpAndSettle();
      expect(ctl.camera.zoom, 5);
      expect(tester.takeException(), isNull);
    });
  });

  group('feedback and zoom controls', () {
    testWidgets('"Tümünü göster" explains itself when there is nothing to show', (tester) async {
      await openMap(tester, settings: const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true));
      await tester.tap(find.byTooltip('Tümünü göster'));
      await tester.pump();
      expect(find.textContaining('Gösterilecek konum yok'), findsOneWidget);
    });

    testWidgets('zoom in and zoom out change the scale by one level and respect the limits', (tester) async {
      final ctl = MapController();
      await openMap(tester, mapController: ctl);
      ctl.move(const LatLng(52, 21), 8);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Yakınlaştır'));
      await tester.pumpAndSettle();
      expect(ctl.camera.zoom, 9);
      await tester.tap(find.byTooltip('Uzaklaştır'));
      await tester.tap(find.byTooltip('Uzaklaştır'));
      await tester.pumpAndSettle();
      expect(ctl.camera.zoom, 7);

      ctl.move(const LatLng(52, 21), 18);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Yakınlaştır'));
      await tester.pumpAndSettle();
      expect(ctl.camera.zoom, 18);

      ctl.move(const LatLng(52, 21), 2);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Uzaklaştır'));
      await tester.pumpAndSettle();
      expect(ctl.camera.zoom, 2);
    });

    testWidgets('"Konumum" centres on the saved fixed position and is hidden without one', (tester) async {
      final ctl = MapController();
      await openMap(tester, mapController: ctl);
      ctl.move(const LatLng(0, 0), 4);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Konumum'));
      await tester.pumpAndSettle();
      expect(ctl.camera.center.latitude, closeTo(52.2297, 1e-4));
      expect(ctl.camera.center.longitude, closeTo(21.0122, 1e-4));
      expect(ctl.camera.zoom, greaterThanOrEqualTo(11));
    });

    testWidgets('no "Konumum" button when no fixed position is set', (tester) async {
      await openMap(tester, settings: const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true));
      expect(find.byTooltip('Konumum'), findsNothing);
      expect(find.byTooltip('Yakınlaştır'), findsOneWidget);
    });
  });
}
