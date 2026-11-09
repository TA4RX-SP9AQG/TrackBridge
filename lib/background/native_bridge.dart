import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import '../state/message_notifier.dart';

/// Connects Dart to the Kotlin code that owns the message notifications shown by
/// Android and by Android Auto.
///
/// Dart -> native: `showMessage`, `clearMessages`.
/// Native -> Dart: `reply` (a voice reply dictated in the car) and `markRead`.
///
/// The channel lives on the Flutter engine that [TrackBridgeApplication] creates, so native code can
/// call into Dart even when no activity exists (the phone is locked and only the car is in use).
class NativeMessageBridge implements MessageNotifier {
  NativeMessageBridge({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'trackbridge/native';

  final MethodChannel _channel;

  /// Starts answering calls from native code.
  void attach(AppController controller) {
    _channel.setMethodCallHandler((call) => _handle(controller, call));
  }

  void detach() => _channel.setMethodCallHandler(null);

  Future<Object?> _handle(AppController controller, MethodCall call) async {
    final args = call.arguments is Map ? (call.arguments as Map).cast<Object?, Object?>() : const <Object?, Object?>{};
    switch (call.method) {
      case 'reply':
        final peer = args['peer'];
        final text = args['text'];
        if (peer is! String || text is! String) {
          return <String, Object?>{'sent': false, 'spoken': 'Yanıt anlaşılamadı.'};
        }
        final result = await controller.replyFromCar(peer, text);
        return <String, Object?>{'sent': result.sent, 'spoken': result.spoken, 'text': result.sentText};
      case 'markRead':
        final peer = args['peer'];
        if (peer is String) await controller.markRead(peer);
        return <String, Object?>{'ok': true};
      default:
        return <String, Object?>{'ok': false};
    }
  }

  @override
  Future<void> showIncoming({
    required String peer,
    required String text,
    required DateTime time,
    required int unread,
    String? messageId,
  }) async {
    try {
      await _channel.invokeMethod<void>('showMessage', <String, Object?>{
        'peer': peer,
        'text': text,
        'timeMillis': time.millisecondsSinceEpoch,
        'unread': unread,
        'id': messageId,
      });
    } on PlatformException {
      // A notification that cannot be shown must never lose the message itself.
    } on MissingPluginException {
      // No native side (tests, desktop).
    }
  }

  @override
  Future<void> clear(String peer) async {
    try {
      await _channel.invokeMethod<void>('clearMessages', <String, Object?>{'peer': peer});
    } on PlatformException {
      // Nothing to clear.
    } on MissingPluginException {
      // No native side.
    }
  }
}
