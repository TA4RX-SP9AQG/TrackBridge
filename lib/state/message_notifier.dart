/// Shows a new incoming message outside the app: in the notification shade and,
/// through Android Auto, in the car.
abstract class MessageNotifier {
  /// [unread] is the number of unread messages in the conversation, including this one.
  Future<void> showIncoming({
    required String peer,
    required String text,
    required DateTime time,
    required int unread,
    String? messageId,
  });

  /// Removes the notification of the conversation with [peer] (it was read).
  Future<void> clear(String peer);
}

/// Does nothing. Used in tests and where notifications are not available.
class NoopMessageNotifier implements MessageNotifier {
  const NoopMessageNotifier();

  @override
  Future<void> showIncoming({
    required String peer,
    required String text,
    required DateTime time,
    required int unread,
    String? messageId,
  }) async {}

  @override
  Future<void> clear(String peer) async {}
}
