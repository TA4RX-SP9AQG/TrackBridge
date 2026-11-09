import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/car_reply.dart';
import 'package:trackbridge/state/models.dart';

import 'helpers/fakes.dart';

late FakeLink link;
late AppController controller;
late DateTime clock;

Future<void> build({
  bool enabled = true,
  String callsign = 'N0DEMO-9',
  bool connected = true,
}) async {
  link = FakeLink();
  clock = DateTime(2026, 11, 9, 8);
  controller = AppController(
    link: link,
    store: MemoryStore(
      AppSettings(
        callsign: callsign,
        noticeAccepted: true,
        autoAck: false,
        carVoiceReply: enabled,
      ),
    ),
    now: () => clock,
  );
  await controller.init();
  if (connected) link.setConnected(true);
  await pump();
}

Future<void> hearFrom(String peer, String text, {String id = '1'}) async {
  link.receive(frameBytes(peer, 'APRS', ':N0DEMO-9 :$text{$id'));
  await pump();
}

void main() {
  test('voice reply is off by default', () {
    expect(const AppSettings().carVoiceReply, isFalse);
  });

  group('replyFromCar', () {
    tearDown(() => controller.dispose());

    test('while the setting is off nothing is transmitted', () async {
      await build(enabled: false);
      await hearFrom('N1TEST-7', 'Selam');
      final r = await controller.replyFromCar('N1TEST-7', 'Tamam');
      expect((r.sent, r.refusal), (false, CarReplyRefusal.disabled));
      expect(link.written, isEmpty);
      expect(r.spoken, contains('kapalı'));
    });

    test(
      'replies to someone who messaged us, in plain ASCII, without a confirmation step',
      () async {
        await build();
        await hearFrom('N1TEST-7', 'Selam');
        final r = await controller.replyFromCar(
          'N1TEST-7',
          'Tamam, 5 dakikada geliyorum ğüşiöç',
        );
        expect(r.sent, isTrue);
        expect(r.sentText, 'Tamam, 5 dakikada geliyorum gusioc');
        expect(
          decodeWritten(link.written.single),
          matches(
            r'^N0DEMO-9>APLRT1,WIDE1-1::N1TEST-7 :Tamam, 5 dakikada geliyorum gusioc\{\d+$',
          ),
        );
        final last = controller.conversations['N1TEST-7']!.last;
        expect(
          (last.direction, last.state),
          (MessageDirection.outgoing, DeliveryState.sent),
        );
        expect(r.spoken, contains('gönderildi'));
      },
    );

    test(
      'refuses a peer that never messaged us (cannot start a conversation by voice)',
      () async {
        await build();
        await hearFrom('N1TEST-7', 'Selam');
        final r = await controller.replyFromCar('N9OTHER-1', 'Merhaba');
        expect(r.refusal, CarReplyRefusal.unknownPeer);
        expect(link.written, isEmpty);
      },
    );

    test('refuses when no tracker is connected', () async {
      await build(connected: false);
      // a stored conversation can exist even when disconnected: hear it first while connected
      link.setConnected(true);
      await hearFrom('N1TEST-7', 'Selam');
      link.setConnected(false);
      await pump();
      final r = await controller.replyFromCar('N1TEST-7', 'Tamam');
      expect(r.refusal, CarReplyRefusal.notConnected);
      expect(r.spoken, contains('bağlı değil'));
    });

    test('refuses without a real callsign', () async {
      await build(callsign: 'N0CALL');
      await hearFrom('N1TEST-7', 'Selam');
      final r = await controller.replyFromCar('N1TEST-7', 'Tamam');
      expect(r.refusal, CarReplyRefusal.noCallsign);
    });

    test('refuses text that is empty after conversion to ASCII', () async {
      await build();
      await hearFrom('N1TEST-7', 'Selam');
      final r = await controller.replyFromCar('N1TEST-7', '👍🙂');
      expect(r.refusal, CarReplyRefusal.emptyText);
      expect(link.written, isEmpty);
    });

    test(
      'two replies closer than 20 seconds: the second is refused, then allowed after the gap',
      () async {
        await build();
        await hearFrom('N1TEST-7', 'Selam');
        expect((await controller.replyFromCar('N1TEST-7', 'bir')).sent, isTrue);
        clock = clock.add(const Duration(seconds: 10));
        final early = await controller.replyFromCar('N1TEST-7', 'iki');
        expect(early.refusal, CarReplyRefusal.tooSoon);
        clock = clock.add(const Duration(seconds: 11));
        expect((await controller.replyFromCar('N1TEST-7', 'uc')).sent, isTrue);
        expect(link.written, hasLength(2));
      },
    );

    test(
      'at most ${AppController.maxCarRepliesPerWindow} replies per 10 minutes',
      () async {
        await build();
        await hearFrom('N1TEST-7', 'Selam');
        var sent = 0;
        CarReplyResult? last;
        for (var i = 0; i < AppController.maxCarRepliesPerWindow + 3; i++) {
          last = await controller.replyFromCar('N1TEST-7', 'm$i');
          if (last.sent) sent++;
          clock = clock.add(const Duration(seconds: 25));
        }
        expect(sent, AppController.maxCarRepliesPerWindow);
        expect(last!.refusal, CarReplyRefusal.tooMany);
        clock = clock.add(const Duration(minutes: 11));
        expect(
          (await controller.replyFromCar('N1TEST-7', 'again')).sent,
          isTrue,
        );
      },
    );

    test('a failing tracker write is reported, not silently lost', () async {
      await build();
      await hearFrom('N1TEST-7', 'Selam');
      link.writeError = StateError('GATT error');
      final r = await controller.replyFromCar('N1TEST-7', 'Tamam');
      expect((r.sent, r.refusal), (false, CarReplyRefusal.failed));
      expect(r.spoken, contains('gönderilemedi'));
      expect(
        controller.conversations['N1TEST-7']!.where(
          (m) => m.direction == MessageDirection.outgoing,
        ),
        isEmpty,
      );
    });

    test(
      'peer names are matched like conversation keys (case, SSID zero)',
      () async {
        await build();
        await hearFrom('N1TEST', 'Selam');
        expect(
          (await controller.replyFromCar('n1test-0', 'tamam')).sent,
          isTrue,
        );
      },
    );
  });
}
