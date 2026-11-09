import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/background/native_bridge.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';

import 'helpers/fakes.dart';

const MethodChannel channel = MethodChannel(NativeMessageBridge.channelName);

late List<MethodCall> sent;
late FakeLink link;
late AppController controller;
late NativeMessageBridge bridge;

Future<void> build({bool voiceReply = true}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sent = [];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    sent.add(call);
    return null;
  });
  link = FakeLink();
  bridge = NativeMessageBridge();
  controller = AppController(
    link: link,
    store: MemoryStore(AppSettings(callsign: 'N0DEMO-9', noticeAccepted: true, autoAck: false, carVoiceReply: voiceReply)),
    notifier: bridge,
    now: () => DateTime(2026, 11, 9, 8),
  );
  await controller.init();
  bridge.attach(controller);
  link.setConnected(true);
  await pump();
}

Future<Map<Object?, Object?>> invoke(String method, Map<String, Object?> args) async {
  final data = const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
  ByteData? out;
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    NativeMessageBridge.channelName,
    data,
    (reply) => out = reply,
  );
  return (const StandardMethodCodec().decodeEnvelope(out!)! as Map).cast<Object?, Object?>();
}

void main() {
  tearDown(() {
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('a new incoming message is forwarded to native code with the unread count', () async {
    await build();
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Merhaba{5'));
    await pump();
    expect(sent, hasLength(1));
    expect(sent.single.method, 'showMessage');
    final args = (sent.single.arguments as Map).cast<String, Object?>();
    expect(args['peer'], 'N1TEST-7');
    expect(args['text'], 'Merhaba');
    expect(args['unread'], 1);
    expect(args['id'], '5');
    expect(args['timeMillis'], DateTime(2026, 11, 9, 8).millisecondsSinceEpoch);
  });

  test('marking read tells native code to remove the notification', () async {
    await build();
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Merhaba{5'));
    await pump();
    await controller.markRead('N1TEST-7');
    expect(sent.last.method, 'clearMessages');
    expect((sent.last.arguments as Map)['peer'], 'N1TEST-7');
  });

  test('native "markRead" clears the unread count', () async {
    await build();
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Merhaba{5'));
    await pump();
    final result = await invoke('markRead', {'peer': 'N1TEST-7'});
    expect(result['ok'], isTrue);
    expect(controller.unreadCount('N1TEST-7'), 0);
  });

  test('native "reply" goes through the safety checks and returns what to say to the driver', () async {
    await build();
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Merhaba{5'));
    await pump();
    final result = await invoke('reply', {'peer': 'N1TEST-7', 'text': 'Tamam, geliyorum ğüş'});
    expect(link.written, hasLength(1));
    expect(result['sent'], isTrue);
    expect(result['spoken'], contains('gönderildi'));
    expect(result['text'], 'Tamam, geliyorum gus');
  });

  test('native "reply" is refused when voice reply is off, and nothing is written', () async {
    await build(voiceReply: false);
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Merhaba{5'));
    await pump();
    final result = await invoke('reply', {'peer': 'N1TEST-7', 'text': 'Tamam'});
    expect(result['sent'], isFalse);
    expect(result['spoken'], contains('kapalı'));
    expect(link.written, isEmpty);
  });

  test('malformed calls from native code are answered, not thrown', () async {
    await build();
    final a = await invoke('reply', {'peer': 5, 'text': null});
    expect(a['sent'], isFalse);
    final b = await invoke('unknownMethod', {});
    expect(b, isNotNull);
  });

  test('a platform error while showing a message does not break the controller', () async {
    await build();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'boom');
    });
    link.receive(frameBytes('N1TEST-7', 'APRS', ':N0DEMO-9 :Merhaba{5'));
    await pump();
    expect(controller.conversations['N1TEST-7'], hasLength(1));
  });
}
