import 'package:trackbridge/state/message_notifier.dart';
import 'package:trackbridge/state/message_store.dart';
import 'package:trackbridge/state/models.dart';

class ShownMessage {
  const ShownMessage({required this.peer, required this.text, required this.unread, this.messageId});

  final String peer;
  final String text;
  final int unread;
  final String? messageId;
}

/// Records what would have been shown in the notification shade and in the car.
class FakeMessageNotifier implements MessageNotifier {
  final List<ShownMessage> shown = [];
  final List<String> cleared = [];

  @override
  Future<void> showIncoming({
    required String peer,
    required String text,
    required DateTime time,
    required int unread,
    String? messageId,
  }) async {
    shown.add(ShownMessage(peer: peer, text: text, unread: unread, messageId: messageId));
  }

  @override
  Future<void> clear(String peer) async => cleared.add(peer);
}

class MemoryMessageStore implements MessageStore {
  MemoryMessageStore([Map<String, List<ChatMessage>>? initial]) : saved = initial ?? {};

  Map<String, List<ChatMessage>> saved;
  int saves = 0;

  @override
  Future<Map<String, List<ChatMessage>>> load() async => saved;

  @override
  Future<void> save(Map<String, List<ChatMessage>> conversations) async {
    saved = conversations;
    saves++;
  }
}
