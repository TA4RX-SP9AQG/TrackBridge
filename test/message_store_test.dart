import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackbridge/state/message_store.dart';
import 'package:trackbridge/state/models.dart';

ChatMessage msg(String peer, int n, {MessageDirection dir = MessageDirection.incoming, DeliveryState state = DeliveryState.none}) =>
    ChatMessage(
      direction: dir,
      peer: peer,
      text: 'mesaj $n',
      time: DateTime(2026, 11, 9, 8).add(Duration(minutes: n)),
      messageId: '$n',
      state: state,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('empty store loads as empty', () async {
    expect(await PrefsMessageStore().load(), isEmpty);
  });

  test('round trip keeps direction, text, time, id and delivery state', () async {
    final store = PrefsMessageStore();
    await store.save({
      'N1TEST-7': [msg('N1TEST-7', 1), msg('N1TEST-7', 2, dir: MessageDirection.outgoing, state: DeliveryState.acked)],
    });
    final loaded = await store.load();
    final list = loaded['N1TEST-7']!;
    expect(list, hasLength(2));
    expect((list[0].direction, list[0].text, list[0].messageId), (MessageDirection.incoming, 'mesaj 1', '1'));
    expect((list[1].direction, list[1].state), (MessageDirection.outgoing, DeliveryState.acked));
    expect(list[1].time, DateTime(2026, 11, 9, 8, 2));
  });

  test('corrupt stored data is ignored instead of crashing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'tb.messages': '{not json'});
    expect(await PrefsMessageStore().load(), isEmpty);
    SharedPreferences.setMockInitialValues(<String, Object>{'tb.messages': '{"N1":[{"x":1}]}'});
    expect(await PrefsMessageStore().load(), isEmpty);
  });

  group('trimming', () {
    test('at most perPeerCap messages per peer, newest kept', () {
      final many = [for (var i = 0; i < PrefsMessageStore.perPeerCap + 30; i++) msg('A1', i)];
      final trimmed = PrefsMessageStore.trim({'A1': many});
      expect(trimmed['A1'], hasLength(PrefsMessageStore.perPeerCap));
      expect(trimmed['A1']!.last.text, 'mesaj ${PrefsMessageStore.perPeerCap + 29}');
      expect(trimmed['A1']!.first.text, 'mesaj 30');
    });

    test('at most totalCap messages overall, oldest dropped first across peers', () {
      final a = [for (var i = 0; i < 200; i++) msg('A1', i)];
      final b = [for (var i = 300; i < 500; i++) msg('B1', i)];
      final c = [for (var i = 600; i < 800; i++) msg('C1', i)];
      final trimmed = PrefsMessageStore.trim({'A1': a, 'B1': b, 'C1': c});
      final total = trimmed.values.fold<int>(0, (n, l) => n + l.length);
      expect(total, PrefsMessageStore.totalCap);
      expect(trimmed['C1'], hasLength(200)); // newest peer untouched
      expect(trimmed['A1']!.length, lessThan(200)); // the oldest lost the most
    });

    test('peers left without messages are removed', () {
      final trimmed = PrefsMessageStore.trim({'A1': const [], 'B1': [msg('B1', 1)]});
      expect(trimmed.keys, ['B1']);
    });
  });

  test('ChatMessage JSON round trip', () {
    final m = msg('N1TEST-7', 5, dir: MessageDirection.outgoing, state: DeliveryState.heardBack);
    final back = ChatMessage.fromJson(m.toJson());
    expect((back.peer, back.text, back.messageId, back.state, back.direction), ('N1TEST-7', 'mesaj 5', '5', DeliveryState.heardBack, MessageDirection.outgoing));
    expect(back.time, m.time);
  });

  test('ChatMessage.fromJson rejects broken input', () {
    expect(() => ChatMessage.fromJson(<String, Object?>{'peer': 1}), throwsFormatException);
  });
}
