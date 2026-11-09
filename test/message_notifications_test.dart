import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';

import 'helpers/fakes.dart';
import 'helpers/message_fakes.dart';

late FakeLink link;
late FakeMessageNotifier notifier;
late MemoryMessageStore store;
late AppController controller;

Future<void> build({Map<String, List<ChatMessage>>? stored}) async {
  link = FakeLink();
  notifier = FakeMessageNotifier();
  store = MemoryMessageStore(stored);
  controller = AppController(
    link: link,
    store: MemoryStore(const AppSettings(callsign: 'N0DEMO-9', noticeAccepted: true, autoAck: false)),
    notifier: notifier,
    messageStore: store,
    now: () => DateTime(2026, 11, 9, 8),
  );
  await controller.init();
  link.setConnected(true);
  await pump();
}

Future<void> hear(String peer, String text, {String id = '1', List<String> path = const []}) async {
  link.receive(frameBytes(peer, 'APRS', ':N0DEMO-9 :$text{$id', path: path));
  await pump();
}

void main() {
  tearDown(() => controller.dispose());

  group('notifications', () {
    test('a new incoming message is notified once, with the unread count', () async {
      await build();
      await hear('N1TEST-7', 'Merhaba');
      expect(notifier.shown, hasLength(1));
      expect((notifier.shown.single.peer, notifier.shown.single.text, notifier.shown.single.unread), ('N1TEST-7', 'Merhaba', 1));
      await hear('N1TEST-7', 'Ikinci', id: '2');
      expect(notifier.shown.last.unread, 2);
    });

    test('the digipeated copy of the same message is not notified again', () async {
      await build();
      await hear('N1TEST-7', 'Merhaba');
      await hear('N1TEST-7', 'Merhaba', path: ['SP9KKK-2*']);
      expect(notifier.shown, hasLength(1));
      expect(controller.unreadCount('N1TEST-7'), 1);
    });

    test('acks, our own echoes and messages for others never notify', () async {
      await build();
      link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :ack5'));
      link.receive(frameBytes('N0DEMO-9', 'APRS', ':N1TEST-7 :hello{3', path: ['SP9KKK-2*']));
      link.receive(frameBytes('N1TEST-7', 'APRS', ':N5ELSE-1 :hi{4'));
      await pump();
      expect(notifier.shown, isEmpty);
    });

    test('no notification while that chat is open and the app is in front', () async {
      await build();
      controller.setAppForeground(true);
      controller.setActiveChat('N1TEST-7');
      await hear('N1TEST-7', 'Merhaba');
      expect(notifier.shown, isEmpty);
      expect(controller.unreadCount('N1TEST-7'), 0);
    });

    test('a different chat open, or the app in the background, still notifies', () async {
      await build();
      controller.setAppForeground(true);
      controller.setActiveChat('N9OTHER-1');
      await hear('N1TEST-7', 'Merhaba');
      expect(notifier.shown, hasLength(1));
      controller.setAppForeground(false);
      controller.setActiveChat('N1TEST-7');
      await hear('N1TEST-7', 'Yine', id: '2');
      expect(notifier.shown, hasLength(2));
    });
  });

  group('read state', () {
    test('markRead clears the unread count and the notification', () async {
      await build();
      await hear('N1TEST-7', 'Merhaba');
      await hear('N2TEST-8', 'Selam', id: '9');
      expect(controller.totalUnread, 2);
      await controller.markRead('N1TEST-7');
      expect(controller.unreadCount('N1TEST-7'), 0);
      expect(controller.totalUnread, 1);
      expect(notifier.cleared, ['N1TEST-7']);
    });

    test('opening a chat marks it read', () async {
      await build();
      await hear('N1TEST-7', 'Merhaba');
      controller.setActiveChat('N1TEST-7');
      await pump();
      expect(controller.unreadCount('N1TEST-7'), 0);
      expect(notifier.cleared, contains('N1TEST-7'));
    });

    test('marking an unknown peer read is harmless', () async {
      await build();
      await controller.markRead('N0NONE-1');
      expect(controller.totalUnread, 0);
    });
  });

  group('persistence', () {
    test('messages are saved after every change', () async {
      await build();
      await hear('N1TEST-7', 'Merhaba');
      await pump();
      expect(store.saves, greaterThan(0));
      expect(store.saved['N1TEST-7']!.single.text, 'Merhaba');
    });

    test('stored conversations are loaded at start and a re-heard old message is not duplicated', () async {
      final old = ChatMessage(
        direction: MessageDirection.incoming,
        peer: 'N1TEST-7',
        text: 'Eski mesaj',
        time: DateTime(2026, 11, 8, 20),
        messageId: '7',
      );
      await build(stored: {'N1TEST-7': [old]});
      expect(controller.conversations['N1TEST-7']!.single.text, 'Eski mesaj');
      await hear('N1TEST-7', 'Eski mesaj', id: '7', path: ['SP9KKK-2*']);
      expect(controller.conversations['N1TEST-7'], hasLength(1));
      expect(notifier.shown, isEmpty);
    });

    test('stored messages start as read (nothing is re-notified after a restart)', () async {
      final old = ChatMessage(
        direction: MessageDirection.incoming,
        peer: 'N1TEST-7',
        text: 'Eski',
        time: DateTime(2026, 11, 8),
        messageId: '1',
      );
      await build(stored: {'N1TEST-7': [old]});
      expect(controller.totalUnread, 0);
    });

    test('delivery state changes are saved too', () async {
      await build();
      await hear('N1TEST-7', 'Selam');
      final p = controller.buildMessagePacket(to: 'N1TEST-7', text: 'Cevap');
      await controller.transmit(p);
      link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :ack${p.messageId}'));
      await pump();
      expect(store.saved['N1TEST-7']!.last.state, DeliveryState.acked);
    });
  });
}
