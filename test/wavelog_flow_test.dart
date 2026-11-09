import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/state/settings_store.dart';
import 'package:trackbridge/state/wavelog_client.dart';
import 'package:trackbridge/ui/app_theme.dart';
import 'package:trackbridge/ui/messages_page.dart';

import 'helpers/fakes.dart';

class FakeWavelog extends WavelogClient {
  FakeWavelog() : super(post: (_, _, _) async => const HttpReply(200, '{}'));

  final List<(WavelogConfig, String)> logged = [];
  WavelogResult next = const WavelogResult(true, 'Wavelog\'a kaydedildi.');

  @override
  Future<WavelogResult> logQso(WavelogConfig c, String adif) async {
    logged.add((c, adif));
    return next;
  }

  @override
  Future<WavelogResult> testConnection(WavelogConfig c) async => next;
}

const configured = AppSettings(
  callsign: 'SP9AQG-9',
  noticeAccepted: true,
  autoAck: false,
  wavelogUrl: 'https://log.example.com',
  wavelogKey: 'KEY123',
  wavelogProfileId: '2',
  wavelogFreqMhz: 433.775,
);

late FakeLink link;
late FakeWavelog wavelog;
late AppController controller;

Future<void> build(AppSettings settings) async {
  link = FakeLink();
  wavelog = FakeWavelog();
  controller = AppController(
    link: link,
    store: MemoryStore(settings),
    wavelog: wavelog,
    now: () => DateTime.utc(2026, 11, 9, 7, 5, 9),
  );
  await controller.init();
  link.setConnected(true);
  await pump();
}

Future<void> hear(String peer, String text) async {
  link.receive(frameBytes(peer, 'APRS', ':SP9AQG-9 :$text{1'));
  await pump();
}

void main() {
  group('settings', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('Wavelog is not configured by default', () {
      const s = AppSettings();
      expect(s.wavelogUrl, '');
      expect(s.wavelogFreqMhz, 433.775);
      expect(s.wavelogConfig.isComplete, isFalse);
    });

    test('Wavelog settings round-trip through the store', () async {
      final store = PrefsSettingsStore();
      await store.save(configured);
      final back = await store.load();
      expect((back.wavelogUrl, back.wavelogKey, back.wavelogProfileId, back.wavelogFreqMhz),
          ('https://log.example.com', 'KEY123', '2', 433.775));
      expect(back.wavelogConfig.isComplete, isTrue);
    });
  });

  group('controller', () {
    tearDown(() => controller.dispose());

    test('logging a conversation sends an ADIF record for that station', () async {
      await build(configured);
      await hear('TA4RX-7', 'Merhaba');
      final r = await controller.logToWavelog('TA4RX-7');
      expect(r.ok, isTrue);
      final adif = wavelog.logged.single.$2;
      expect(adif, contains('<CALL:5>TA4RX'));
      expect(adif, contains('<STATION_CALLSIGN:6>SP9AQG'));
      expect(adif, contains('<QSO_DATE:8>20261109'));
      expect(adif, contains('<TIME_ON:6>070509'));
      expect(adif, contains('<FREQ:7>433.775'));
      expect(wavelog.logged.single.$1.stationProfileId, '2');
    });

    test('the QSO time is the first message of the conversation', () async {
      await build(configured);
      await hear('TA4RX-7', 'Merhaba');
      expect(controller.preview('TA4RX-7')!.timeUtc, DateTime.utc(2026, 11, 9, 7, 5, 9));
    });

    test('refuses without configuration and sends nothing', () async {
      await build(const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true, autoAck: false));
      await hear('TA4RX-7', 'Merhaba');
      final r = await controller.logToWavelog('TA4RX-7');
      expect(r.ok, isFalse);
      expect(wavelog.logged, isEmpty);
    });

    test('refuses a station we have no conversation with', () async {
      await build(configured);
      expect((await controller.logToWavelog('N9NONE-1')).ok, isFalse);
      expect(wavelog.logged, isEmpty);
    });

    test('refuses without a real own callsign', () async {
      await build(configured.copyWith(callsign: 'N0CALL'));
      await hear('TA4RX-7', 'Merhaba');
      expect((await controller.logToWavelog('TA4RX-7')).ok, isFalse);
      expect(wavelog.logged, isEmpty);
    });

    test('the server answer is passed on', () async {
      await build(configured);
      await hear('TA4RX-7', 'Merhaba');
      wavelog.next = const WavelogResult(false, 'Wavelog reddetti: invalid api key');
      final r = await controller.logToWavelog('TA4RX-7');
      expect(r.ok, isFalse);
      expect(r.message, contains('invalid api key'));
    });
  });

  group('chat screen', () {
    tearDown(() => controller.dispose());

    Future<void> openChat(WidgetTester tester, AppSettings s) async {
      // The shared helpers wait on a real zero-length timer, which a widget test's fake clock never fires.
      await tester.runAsync(() async {
        await build(s);
        await hear('TA4RX-7', 'Merhaba');
      });
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: ChatPage(controller: controller, peer: 'TA4RX-7')));
      await tester.pump();
    }

    testWidgets('no Wavelog button when Wavelog is not configured', (tester) async {
      await openChat(tester, const AppSettings(callsign: 'SP9AQG-9', noticeAccepted: true, autoAck: false));
      expect(find.byTooltip('Wavelog\'a kaydet'), findsNothing);
    });

    testWidgets('the button asks first, showing the destination and the record, and sends nothing until confirmed', (tester) async {
      await openChat(tester, configured);
      await tester.tap(find.byTooltip('Wavelog\'a kaydet'));
      await tester.pumpAndSettle();
      expect(find.textContaining('log.example.com'), findsWidgets);
      expect(find.textContaining('TA4RX'), findsWidgets);
      expect(wavelog.logged, isEmpty);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
      expect(wavelog.logged, isEmpty);
    });

    testWidgets('confirming sends it and shows the result', (tester) async {
      await openChat(tester, configured);
      await tester.tap(find.byTooltip('Wavelog\'a kaydet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(wavelog.logged, hasLength(1));
      expect(find.textContaining('kaydedildi'), findsWidgets);
    });
  });
}
