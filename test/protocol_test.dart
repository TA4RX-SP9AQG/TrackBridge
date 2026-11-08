import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/aprs.dart';
import 'package:trackbridge/core/ax25.dart';
import 'package:trackbridge/core/kiss_codec.dart';

Uint8List hexBytes(String hex) => Uint8List.fromList(
    hex.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).map((s) => int.parse(s, radix: 16)).toList());

String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');

// Frames captured from a real tracker during the browser/PC tests.
const messageFrameHex =
    'c0 00 82 a0 98 a4 a8 62 60 a6 a0 72 82 a2 8e 72 ae 92 88 8a 62 40 63 03 f0 3a 54 41 34 52 58 2d 37 20 20 3a '
    '4d 65 72 68 61 62 61 20 54 41 34 52 58 2d 37 2c 20 42 4c 45 20 6d 65 73 61 6a 20 74 65 73 74 69 7b 31 c0';

const digipeatedFrameHex =
    'c0 00 82 a0 98 a4 a8 62 60 a6 a0 72 82 a2 8e 72 a6 a0 72 96 96 96 e5 03 f0 3a 54 41 34 52 58 2d 37 20 20 3a '
    '4d 65 72 68 61 62 61 20 54 41 34 52 58 2d 37 2c 20 42 4c 45 20 6d 65 73 61 6a 20 74 65 73 74 69 7b 31 c0';

void main() {
  group('KISS codec', () {
    test('encode escapes FEND and FESC', () {
      final out = kissEncode(Uint8List.fromList([0x41, kFend, kFesc, 0x42]));
      expect(toHex(out), 'c0 00 41 db dc db dd 42 c0');
    });

    test('deframer decodes one frame and unescapes', () {
      final d = KissDeframer();
      final frames = d.add(hexBytes('c0 00 41 db dc db dd 42 c0'));
      expect(frames, hasLength(1));
      expect(frames.first.command, 0);
      expect(toHex(frames.first.data), '41 c0 db 42');
    });

    test('deframer reassembles a frame split across notifications', () {
      final bytes = hexBytes(messageFrameHex);
      final d = KissDeframer();
      expect(d.add(bytes.sublist(0, 10)), isEmpty);
      expect(d.add(bytes.sublist(10, 40)), isEmpty);
      final frames = d.add(bytes.sublist(40));
      expect(frames, hasLength(1));
    });

    test('deframer handles two back-to-back frames and garbage before FEND', () {
      final d = KissDeframer();
      final frames = d.add(hexBytes('11 22 c0 00 01 c0 c0 00 02 c0'));
      expect(frames.map((f) => toHex(f.data)).toList(), ['01', '02']);
    });

    test('deframer ignores empty frames and keeps working', () {
      final d = KissDeframer();
      expect(d.add(hexBytes('c0 c0 c0')), isEmpty);
      expect(d.add(hexBytes('00 07 c0')), hasLength(1));
    });

    test('deframer drops oversized garbage without growing forever', () {
      final d = KissDeframer();
      d.add([kFend, ...List.filled(KissDeframer.maxBuffer + 10, 0x41)]);
      expect(d.bufferedBytes, lessThanOrEqualTo(KissDeframer.maxBuffer));
    });
  });

  group('AX.25', () {
    test('encodes the golden message frame byte for byte', () {
      final frame = Ax25Frame(
        destination: Ax25Address.parse('APLRT1'),
        source: Ax25Address.parse('SP9AQG-9'),
        digipeaters: [Ax25Address.parse('WIDE1-1')],
        info: Uint8List.fromList(':TA4RX-7  :Merhaba TA4RX-7, BLE mesaj testi{1'.codeUnits),
      );
      expect(toHex(kissEncode(frame.encode())), messageFrameHex);
    });

    test('decodes a digipeated frame with H bit', () {
      final kiss = KissDeframer().add(hexBytes(digipeatedFrameHex)).single;
      final frame = Ax25Frame.decode(kiss.data)!;
      expect(frame.toTnc2(), 'SP9AQG-9>APLRT1,SP9KKK-2*::TA4RX-7  :Merhaba TA4RX-7, BLE mesaj testi{1');
      expect(frame.digipeaters.single.repeated, isTrue);
    });

    test('decode returns null for truncated data', () {
      expect(Ax25Frame.decode(Uint8List.fromList([1, 2, 3])), isNull);
    });

    test('decode rejects frames that are not UI (control 0x03) with PID 0xF0', () {
      final data = Uint8List.fromList(KissDeframer().add(hexBytes(digipeatedFrameHex)).single.data);
      final badControl = Uint8List.fromList(data)..[data.length - 1 - 'x'.length] = 0;
      expect(Ax25Frame.decode(badControl), isNotNull); // info byte changed only: still a UI frame
      final offset = 7 + 7 + 7; // dst + src + one digipeater
      expect(Ax25Frame.decode(Uint8List.fromList(data)..[offset] = 0x13), isNull);
      expect(Ax25Frame.decode(Uint8List.fromList(data)..[offset + 1] = 0xCF), isNull);
    });

    test('command bit on destination/source is not shown as repeated', () {
      final data = Uint8List.fromList(KissDeframer().add(hexBytes(digipeatedFrameHex)).single.data)..[6] = 0xE0;
      final frame = Ax25Frame.decode(data)!;
      expect(frame.destination.repeated, isFalse);
      expect(frame.toTnc2(), startsWith('SP9AQG-9>APLRT1,SP9KKK-2*:'));
    });

    test('encode refuses more than 8 digipeaters', () {
      final frame = Ax25Frame(
        destination: Ax25Address.parse('APLRT1'),
        source: Ax25Address.parse('SP9AQG-9'),
        digipeaters: List.generate(9, (i) => Ax25Address.parse('WIDE$i-1')),
        info: Uint8List(0),
      );
      expect(frame.encode, throwsArgumentError);
    });

    test('address parsing validates callsign and ssid', () {
      expect(() => Ax25Address.parse('TOOLONGCALL'), throwsFormatException);
      expect(() => Ax25Address.parse('SP9AQG-16'), throwsFormatException);
      expect(() => Ax25Address.parse('SP9 AQG'), throwsFormatException);
      expect(Ax25Address.parse('sp9aqg-9').toString(), 'SP9AQG-9');
      expect(Ax25Address.parse('SP9KKK-2*').repeated, isTrue);
    });
  });

  group('APRS', () {
    test('builds message info with padded addressee and id', () {
      expect(buildMessageInfo(to: 'TA4RX-7', text: 'Merhaba', id: '1'), ':TA4RX-7  :Merhaba{1');
      expect(buildMessageInfo(to: 'N0CALL', text: 'x'), ':N0CALL   :x');
    });

    test('message text must be ascii and at most 67 chars', () {
      expect(() => buildMessageInfo(to: 'A', text: 'merhaba ş'), throwsFormatException);
      expect(() => buildMessageInfo(to: 'A', text: 'a' * 68), throwsFormatException);
      expect(() => buildMessageInfo(to: 'A', text: 'a{b'), throwsFormatException);
    });

    test('parses incoming message, ack and rej', () {
      final m = parseMessage(':SP9AQG-9 :Selam{12')!;
      expect((m.addressee, m.text, m.id), ('SP9AQG-9', 'Selam', '12'));
      final a = parseMessage(':SP9AQG-9 :ack12')!;
      expect(a.kind, AprsMessageKind.ack);
      expect(a.id, '12');
      expect(parseMessage(':SP9AQG-9 :rej3')!.kind, AprsMessageKind.rej);
      expect(parseMessage('!5213.78N/02100.73E-'), isNull);
    });

    test('parses reply-ack form text{MM}AA', () {
      final m = parseMessage(':SP9AQG-9 :Selam{12}34')!;
      expect((m.kind, m.text, m.id, m.replyAckId), (AprsMessageKind.message, 'Selam', '12', '34'));
      final capableOnly = parseMessage(':SP9AQG-9 :Selam{12}')!;
      expect((capableOnly.id, capableOnly.replyAckId), ('12', null));
      expect(parseMessage(':SP9AQG-9 :Selam{12')!.replyAckId, isNull);
    });

    test('normalizeCallsign drops zero ssid, repeated flag and case', () {
      expect(normalizeCallsign('ta4rx-0'), 'TA4RX');
      expect(normalizeCallsign('TA4RX-7*'), 'TA4RX-7');
      expect(() => normalizeCallsign('bad call'), throwsFormatException);
    });

    test('ack info', () {
      expect(buildAckInfo(to: 'TA4RX-7', id: '5'), ':TA4RX-7  :ack5');
    });

    test('position formats full precision with truncation not rounding', () {
      expect(
        buildPositionInfo(lat: 52.2297, lon: 21.0122, symbolTable: '/', symbol: '-', comment: 'x'),
        '!5213.78N/02100.73E-x',
      );
    });

    test('position ambiguity blanks digits from the right', () {
      String pos(int a) => buildPositionInfo(lat: 52.2297, lon: 21.0122, symbolTable: '/', symbol: '-', ambiguity: a);
      expect(pos(1), '!5213.7 N/02100.7 E-');
      expect(pos(2), '!5213.  N/02100.  E-');
      expect(pos(3), '!521 .  N/0210 .  E-');
      expect(pos(4), '!52  .  N/021  .  E-');
    });

    test('position handles south/west and validates range', () {
      expect(buildPositionInfo(lat: -33.5, lon: -70.25, symbolTable: '/', symbol: '>'), '!3330.00S/07015.00W>');
      expect(() => buildPositionInfo(lat: 91, lon: 0, symbolTable: '/', symbol: '-'), throwsFormatException);
      expect(() => buildPositionInfo(lat: 0, lon: 181, symbolTable: '/', symbol: '-'), throwsFormatException);
    });

    test('callsign validation rejects placeholders', () {
      expect(isUsableCallsign('SP9AQG-9'), isTrue);
      expect(isUsableCallsign('N0CALL'), isFalse);
      expect(isUsableCallsign('N0CALL-7'), isFalse);
      expect(isUsableCallsign(''), isFalse);
      expect(isUsableCallsign('ABCDEFGH'), isFalse);
    });
  });
}
