import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/ble/tracker_link.dart';
import 'package:trackbridge/core/ax25.dart';
import 'package:trackbridge/core/kiss_codec.dart';
import 'package:trackbridge/state/app_controller.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/state/phone_position.dart';
import 'package:trackbridge/state/settings_store.dart';

class FakeLink implements TrackerLink {
  final _info = StreamController<LinkInfo>.broadcast();
  final _incoming = StreamController<Uint8List>.broadcast();
  final List<Uint8List> written = [];
  LinkInfo current = const LinkInfo();
  Object? writeError;

  void setConnected(bool connected) {
    current = LinkInfo(
      status: connected ? LinkStatus.connected : LinkStatus.disconnected,
      deviceId: 'AA:BB',
      deviceName: 'LoRaTracker',
      mtu: 247,
    );
    _info.add(current);
  }

  void receive(Uint8List bytes) => _incoming.add(bytes);

  @override
  LinkInfo get info => current;
  @override
  Stream<LinkInfo> get infoStream => _info.stream;
  @override
  Stream<Uint8List> get incoming => _incoming.stream;
  @override
  Stream<AdapterState> get adapterState => const Stream<AdapterState>.empty();
  @override
  Stream<FoundTracker> scan() => const Stream<FoundTracker>.empty();
  @override
  Future<void> connect(String id, {String? name}) async => setConnected(true);
  @override
  Future<void> disconnect() async => setConnected(false);
  @override
  Future<void> write(Uint8List bytes) async {
    if (!current.isConnected) throw StateError('Tracker bağlı değil.');
    if (writeError != null) throw writeError!;
    written.add(bytes);
  }

  @override
  Future<void> dispose() async {}
}

class MemoryStore implements SettingsStore {
  MemoryStore(this.value);
  AppSettings value;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async => value = settings;
}

Uint8List frameBytes(String src, String dst, String info, {List<String> path = const []}) => kissEncode(
      Ax25Frame(
        destination: Ax25Address.parse(dst),
        source: Ax25Address.parse(src),
        digipeaters: path.map(Ax25Address.parse).toList(),
        info: Uint8List.fromList(info.codeUnits),
      ).encode(),
    );

String decodeWritten(Uint8List kiss) {
  final frame = KissDeframer().add(kiss).single;
  return Ax25Frame.decode(frame.data)!.toTnc2();
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeLink link;
  late MemoryStore store;
  late DateTime clock;
  late AppController controller;

  Future<AppController> build({AppSettings? settings, PositionProvider? position}) async {
    link = FakeLink();
    store = MemoryStore(settings ??
        const AppSettings(
          callsign: 'SP9AQG-9',
          manualLat: 52.2297,
          manualLon: 21.0122,
          noticeAccepted: true,
        ));
    clock = DateTime(2026, 11, 8, 12);
    controller = AppController(link: link, store: store, positionProvider: position, now: () => clock);
    await controller.init();
    link.setConnected(true);
    await pump();
    return controller;
  }

  tearDown(() => controller.dispose());

  group('building packets', () {
    test('message packet has path, padded addressee and message id', () async {
      await build();
      final p = controller.buildMessagePacket(to: 'ta4rx-7', text: 'Merhaba');
      expect(p.tnc2, matches(r'^SP9AQG-9>APLRT1,WIDE1-1::TA4RX-7  :Merhaba\{\d+$'));
      expect(p.peer, 'TA4RX-7');
      expect(decodeWritten(p.kiss), p.tnc2);
    });

    test('refuses to build without a real callsign', () async {
      await build(settings: const AppSettings());
      expect(() => controller.buildMessagePacket(to: 'TA4RX-7', text: 'x'), throwsFormatException);
      await controller.updateSettings(controller.settings.copyWith(callsign: 'N0CALL'));
      expect(() => controller.buildMessagePacket(to: 'TA4RX-7', text: 'x'), throwsFormatException);
    });

    test('message ids increase', () async {
      await build();
      final a = controller.buildMessagePacket(to: 'TA4RX-7', text: 'a');
      final b = controller.buildMessagePacket(to: 'TA4RX-7', text: 'b');
      expect(int.parse(b.messageId!), int.parse(a.messageId!) + 1);
    });

    test('beacon from manual position is truncated by ambiguity 2', () async {
      await build();
      final p = await controller.buildBeaconPacket();
      expect(p.tnc2, 'SP9AQG-9>APLRT1,WIDE1-1:!5213.  N/02100.  E-TrackBridge');
    });

    test('beacon carries the chosen symbol, including an overlay character in the table field', () async {
      await build();
      await controller.updateSettings(controller.settings.copyWith(symbolTable: 'S', symbol: '#', comment: ''));
      final p = await controller.buildBeaconPacket();
      expect(p.tnc2, 'SP9AQG-9>APLRT1,WIDE1-1:!5213.  NS02100.  E#');
      await controller.updateSettings(controller.settings.copyWith(symbolTable: r'\', symbol: '&'));
      expect((await controller.buildBeaconPacket()).tnc2, endsWith(r'!5213.  N\02100.  E&'));
    });

    test('beacon without a manual position fails with a clear error', () async {
      await build(settings: const AppSettings(callsign: 'SP9AQG-9'));
      expect(controller.buildBeaconPacket(), throwsA(isA<FormatException>()));
    });

    test('beacon from phone uses the injected provider', () async {
      await build(
        settings: const AppSettings(callsign: 'SP9AQG-9', positionSource: PositionSource.phone, ambiguity: 0),
        position: () async => const GeoPoint(52.2297, 21.0122),
      );
      final p = await controller.buildBeaconPacket();
      expect(p.tnc2, contains('!5213.78N/02100.73E-'));
    });

    test('phone position failures become a readable FormatException', () async {
      await build(
        settings: const AppSettings(callsign: 'SP9AQG-9', positionSource: PositionSource.phone),
        position: () async => throw TimeoutException('gps'),
      );
      await expectLater(controller.buildBeaconPacket(), throwsA(isA<FormatException>()));
    });

    test('invalid path is rejected', () async {
      await build();
      await controller.updateSettings(controller.settings.copyWith(path: 'WIDE1-1,BAD CALL'));
      expect(() => controller.buildMessagePacket(to: 'TA4RX-7', text: 'x'), throwsFormatException);
    });
  });

  group('transmitting', () {
    test('transmit writes the KISS bytes and records an outgoing message', () async {
      await build();
      final p = controller.buildMessagePacket(to: 'TA4RX-7', text: 'Selam');
      await controller.transmit(p);
      expect(link.written.single, p.kiss);
      final msg = controller.conversations['TA4RX-7']!.single;
      expect((msg.direction, msg.text, msg.state), (MessageDirection.outgoing, 'Selam', DeliveryState.sent));
    });

    test('transmit fails when not connected and records nothing', () async {
      await build();
      link.setConnected(false);
      await pump();
      final p = controller.buildMessagePacket(to: 'TA4RX-7', text: 'Selam');
      await expectLater(controller.transmit(p), throwsStateError);
      expect(controller.conversations, isEmpty);
    });
  });

  group('receiving', () {
    test('frames split across notifications are reassembled', () async {
      await build();
      final bytes = frameBytes('N1TEST-7', 'APLOX1', '!5213.78N/02100.73E[hello');
      link.receive(Uint8List.sublistView(bytes, 0, 12));
      link.receive(Uint8List.sublistView(bytes, 12));
      await pump();
      expect(controller.heard.single.tnc2, 'N1TEST-7>APLOX1:!5213.78N/02100.73E[hello');
    });

    test('message for us is stored and acked', () async {
      await build();
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :Selam{12'));
      await pump();
      final msg = controller.conversations['TA4RX-7']!.single;
      expect((msg.direction, msg.text, msg.messageId), (MessageDirection.incoming, 'Selam', '12'));
      expect(decodeWritten(link.written.single), 'SP9AQG-9>APLRT1,WIDE1-1::TA4RX-7  :ack12');
    });

    test('digipeated copy of the same message is not shown twice and ack is throttled', () async {
      await build();
      final bytes = frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :Selam{12', path: ['SP9KKK-2*']);
      link.receive(bytes);
      link.receive(bytes);
      await pump();
      expect(controller.conversations['TA4RX-7'], hasLength(1));
      expect(link.written, hasLength(1));
      clock = clock.add(const Duration(seconds: 30));
      link.receive(bytes);
      await pump();
      expect(link.written, hasLength(2)); // sender kept retrying: ack again
      expect(controller.conversations['TA4RX-7'], hasLength(1));
    });

    test('global ack rate limit: a flood of new ids cannot make us transmit without bound', () async {
      await build();
      for (var i = 1; i <= 30; i++) {
        link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :flood{$i}'));
        clock = clock.add(const Duration(seconds: 6)); // beyond the minimum spacing
        await pump();
      }
      expect(link.written.length, lessThanOrEqualTo(AppController.maxAcksPerWindow));
      expect(controller.conversations['TA4RX-7'], hasLength(30)); // still displayed
    });

    test('ack is not sent twice within the minimum spacing for different ids', () async {
      await build();
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :a{1'));
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :b{2'));
      await pump();
      expect(link.written, hasLength(1));
    });

    test('reply-ack: acks the sender and also acknowledges our own message', () async {
      await build();
      final p = controller.buildMessagePacket(to: 'TA4RX-7', text: 'Selam');
      await controller.transmit(p);
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :Cevap{7}${p.messageId}'));
      await pump();
      expect(controller.conversations['TA4RX-7']!.first.state, DeliveryState.acked);
      expect(controller.conversations['TA4RX-7']!.last.text, 'Cevap');
      expect(decodeWritten(link.written.last), endsWith(':ack7'));
    });

    test('no ack when auto-ack is off', () async {
      await build(settings: const AppSettings(callsign: 'SP9AQG-9', autoAck: false));
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :Selam{12'));
      await pump();
      expect(controller.conversations['TA4RX-7'], hasLength(1));
      expect(link.written, isEmpty);
    });

    test('message without id is shown but never acked', () async {
      await build();
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :no id here'));
      await pump();
      expect(controller.conversations['TA4RX-7'], hasLength(1));
      expect(link.written, isEmpty);
    });

    test('message for someone else is only in the heard list', () async {
      await build();
      link.receive(frameBytes('TA4RX-7', 'APRS', ':N0XYZ-1   :hi{3'));
      await pump();
      expect(controller.conversations, isEmpty);
      expect(controller.heard, hasLength(1));
      expect(link.written, isEmpty);
    });

    test('ack and rej update the delivery state of our message', () async {
      await build();
      final p = controller.buildMessagePacket(to: 'TA4RX-7', text: 'Selam');
      await controller.transmit(p);
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :ack${p.messageId}'));
      await pump();
      expect(controller.conversations['TA4RX-7']!.single.state, DeliveryState.acked);

      final q = controller.buildMessagePacket(to: 'TA4RX-7', text: 'Ikinci');
      await controller.transmit(q);
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :rej${q.messageId}'));
      await pump();
      expect(controller.conversations['TA4RX-7']!.last.state, DeliveryState.rejected);
    });

    test('hearing our own message back via a digipeater marks it, and never downgrades an ack', () async {
      await build();
      final p = controller.buildMessagePacket(to: 'TA4RX-7', text: 'Selam');
      await controller.transmit(p);
      final echo = frameBytes('SP9AQG-9', 'APLRT1', ':TA4RX-7  :Selam{${p.messageId}', path: ['SP9KKK-2*']);
      link.receive(echo);
      await pump();
      expect(controller.conversations['TA4RX-7']!.single.state, DeliveryState.heardBack);
      link.receive(frameBytes('TA4RX-7', 'APRS', ':SP9AQG-9 :ack${p.messageId}'));
      link.receive(echo);
      await pump();
      expect(controller.conversations['TA4RX-7']!.single.state, DeliveryState.acked);
      expect(link.written, hasLength(1)); // our own echo is never acked or stored as incoming
    });

    test('heard list is capped', () async {
      await build();
      for (var i = 0; i < AppController.maxHeard + 20; i++) {
        link.receive(frameBytes('N1TEST-7', 'APLOX1', '>status $i'));
      }
      await pump();
      expect(controller.heard.length, AppController.maxHeard);
      expect(controller.heard.first.tnc2, endsWith('status ${AppController.maxHeard + 19}')); // newest first
    });

    test('garbage that is not an AX.25 frame is ignored', () async {
      await build();
      link.receive(Uint8List.fromList([kFend, 0x00, 1, 2, 3, kFend]));
      await pump();
      expect(controller.heard, isEmpty);
    });
  });
}
