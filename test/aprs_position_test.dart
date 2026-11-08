import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/aprs_position.dart';
import 'package:trackbridge/core/ax25.dart';

// Vectors: real Mic-E packets and the APRS101 examples, with expected values taken from the
// independent open-source decoder test suites (aprsme/aprs, rossengeorgiev/aprs-python).

AprsPosition? parse(String destination, String info) => parsePosition(destination: destination, info: info);

void main() {
  group('uncompressed', () {
    test('plain position without timestamp', () {
      final p = parse('APLRT1', '!5213.78N/02100.73E[hello')!;
      expect(p.lat, closeTo(52.229667, 1e-5));
      expect(p.lon, closeTo(21.012167, 1e-5));
      expect((p.symbolTable, p.symbolCode, p.comment), ('/', '[', 'hello'));
      expect(p.format, PositionFormat.uncompressed);
      expect(p.ambiguity, 0);
    });

    test('with timestamp (APRS101 weather example)', () {
      final p = parse('APRS', '@092345z4903.50N/07201.75W_090/001g000t066r000p000...dUII')!;
      expect(p.lat, closeTo(49.058333, 1e-5));
      expect(p.lon, closeTo(-72.029167, 1e-5));
      expect((p.symbolTable, p.symbolCode), ('/', '_'));
      expect(p.courseDeg, 90);
      expect(p.speedKmh, closeTo(1.852, 1e-3));
    });

    test('southern and western hemisphere', () {
      final p = parse('APRS', '=3330.00S/07015.00W>')!;
      expect(p.lat, closeTo(-33.5, 1e-9));
      expect(p.lon, closeTo(-70.25, 1e-9));
    });

    test('ambiguity: blanks are centred in the square, not read as the south-west corner', () {
      final p = parse('APLRT1', '!5213.  N/02100.  E-x')!;
      expect(p.ambiguity, 2);
      expect(p.lat, closeTo(52 + 13.5 / 60, 1e-9));
      expect(p.lon, closeTo(21 + 0.5 / 60, 1e-9));
      expect(parse('A', '!5213.7 N/02100.7 E-')!.ambiguity, 1);
      expect(parse('A', '!5213.7 N/02100.7 E-')!.lat, closeTo(52 + 13.75 / 60, 1e-9));
      expect(parse('A', '!521 .  N/0210 .  E-')!.ambiguity, 3);
      expect(parse('A', '!52  .  N/021  .  E-')!.ambiguity, 4);
      expect(parse('A', '!52  .  N/021  .  E-')!.lat, closeTo(52.5, 1e-9));
    });

    test('course/speed extension and altitude in the comment', () {
      final p = parse('APRS', '!4903.50N/07201.75W>088/036 test/A=001234 more')!;
      expect(p.courseDeg, 88);
      expect(p.speedKmh, closeTo(36 * 1.852, 1e-6));
      expect(p.altitudeM, closeTo(1234 * 0.3048, 1e-6));
      expect(p.comment, 'test more');
    });

    test('course 000 means unknown', () {
      final p = parse('APRS', '!4903.50N/07201.75W>000/000')!;
      expect((p.courseDeg, p.speedKmh), (null, null));
    });

    test('rejects bad coordinates and garbage', () {
      expect(parse('APRS', '!9100.00N/07201.75W>'), isNull); // latitude > 90
      expect(parse('APRS', '!4903.50N/18100.00W>'), isNull); // longitude > 180
      expect(parse('APRS', '!4903.9'), isNull); // truncated
      expect(parse('APRS', '!49O3.50N/07201.75W>'), isNull); // letter inside the digits
      expect(parse('APRS', '!4903.50X/07201.75W>'), isNull); // bad hemisphere
      expect(parse('APRS', ''), isNull);
      expect(parse('APRS', '>status text'), isNull); // not a position packet
      expect(parse('APRS', ':ABCDEFGHI:msg{1'), isNull); // message, not a position
    });
  });

  group('compressed', () {
    test('APRS101 example without course/speed', () {
      final p = parse('APRS', '!/5L!!<*e7> sTComment')!;
      expect(p.lat, closeTo(49.5, 1e-4));
      expect(p.lon, closeTo(-72.75, 1e-4));
      expect((p.symbolTable, p.symbolCode, p.comment), ('/', '>', 'Comment'));
      expect(p.format, PositionFormat.compressed);
      expect((p.courseDeg, p.speedKmh), (null, null));
    });

    test('APRS101 example with course 88 and speed 36 kn', () {
      final p = parse('APRS', '=/5L!!<*e7>7P[')!;
      expect(p.courseDeg, 88);
      expect(p.speedKmh, closeTo(36.2 * 1.852, 0.5));
    });

    test('overlay letters a-j in the table position mean digits 0-9', () {
      final p = parse('APRS', '!a5L!!<*e7> sT')!;
      expect(p.symbolTable, '0');
    });

    test('invalid base91 characters are rejected', () {
      expect(parse('APRS', '!/5L!\u007f<*e7> sT'), isNull);
      expect(parse('APRS', '!/5L!!'), isNull);
    });
  });

  group('Mic-E', () {
    test('real packet KG5EIU-9: position, speed, course, symbol, comment', () {
      final p = parse('S3PS2V', '`|>Fp wj/`"5c}442.425MHz Toff +500 kg5eiu@w5fc.org _4')!;
      expect(p.lat, closeTo(33.054333, 1e-4));
      expect(p.lon, closeTo(-96.573667, 1e-4));
      expect((p.symbolTable, p.symbolCode), ('/', 'j'));
      expect(p.speedKmh, closeTo(40 * 1.852, 1e-6));
      expect(p.courseDeg, 91);
      expect(p.format, PositionFormat.micE);
      expect(p.altitudeM, isNotNull);
    });

    test('real packet K5EEN-14: longitude with zero offset', () {
      final p = parse('S3PW0U', '`|DKo"G>/`"6+}_%')!;
      expect(p.lat, closeTo(33.1175, 1e-4));
      expect(p.lon, closeTo(-96.6745, 1e-4));
      expect((p.symbolTable, p.symbolCode), ('/', '>'));
    });

    test('real packet W5DGK-9: altitude 218 m in the comment, text kept', () {
      final p = parse('S3RS2Y', '`|<yl k/`"6;}Happy Trails ...146.52 or 469-247-2654_% ')!;
      expect(p.lat, closeTo(33.388167, 1e-4));
      expect(p.lon, closeTo(-96.548833, 1e-4));
      expect(p.altitudeM, closeTo(218, 0.01));
      expect(p.comment, contains('Happy Trails'));
      expect(p.comment, isNot(contains('}')));
    });

    test('APRS101 example: speed 20 kn, course 251, longitude offset +100', () {
      final p = parse('T7SYWU', '`(_fn"Oj/')!;
      expect(p.speedKmh, closeTo(20 * 1.852, 1e-6));
      expect(p.courseDeg, 251);
      expect(p.lon, closeTo(-(112 + 7.74 / 60), 1e-4));
      expect(p.lat, closeTo(47 + 39.75 / 60, 1e-4));
    });

    test('old data type character and short or invalid input', () {
      expect(parse('S3PS2V', "'|>Fp wj/")!.lat, closeTo(33.054333, 1e-4));
      expect(parse('SHORT', '`|>Fp wj/'), isNull);
      expect(parse('!!!!!!', '`|>Fp wj/'), isNull);
      expect(parse('S3PS2V', '`|>Fp'), isNull);
    });

    test('SSID on the destination is ignored by the frame wrapper', () {
      final frame = Ax25Frame(
        destination: Ax25Address.parse('S3PS2V-7'),
        source: Ax25Address.parse('KG5EIU-9'),
        info: Uint8List.fromList('`|>Fp wj/'.codeUnits),
      );
      expect(parsePositionFrame(frame)!.lat, closeTo(33.054333, 1e-4));
    });
  });

  group('objects and items', () {
    test('APRS101 object with course and speed', () {
      final p = parse('APRS', ';LEADER   *092345z4903.50N/07201.75W>088/036')!;
      expect(p.objectName, 'LEADER');
      expect(p.killed, isFalse);
      expect(p.lat, closeTo(49.058333, 1e-5));
      expect(p.courseDeg, 88);
    });

    test('killed object', () {
      final p = parse('APRS', ';LEADER   _092345z4903.50N/07201.75W>')!;
      expect(p.killed, isTrue);
    });

    test('item report', () {
      final p = parse('APRS', ')AID #2!4903.50N/07201.75WA')!;
      expect(p.objectName, 'AID #2');
      expect(p.symbolCode, 'A');
    });

    test('object with compressed position', () {
      final p = parse('APRS', ';LEADER   *092345z/5L!!<*e7>7P[')!;
      expect(p.objectName, 'LEADER');
      expect(p.lat, closeTo(49.5, 1e-4));
    });
  });

  group('frame wrapper', () {
    test('uses the info field of an AX.25 frame and returns null for non-positions', () {
      Ax25Frame f(String info) => Ax25Frame(
            destination: Ax25Address.parse('APLRT1'),
            source: Ax25Address.parse('N1TEST-7'),
            info: Uint8List.fromList(info.codeUnits),
          );
      expect(parsePositionFrame(f('!5213.78N/02100.73E-'))!.lat, closeTo(52.229667, 1e-5));
      expect(parsePositionFrame(f(':N0XYZ-1  :hi{1')), isNull);
    });
  });
}
