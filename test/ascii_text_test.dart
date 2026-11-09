import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/ascii_text.dart';

void main() {
  group('toAprsAscii', () {
    test('Turkish letters', () {
      expect(toAprsAscii('Merhaba dünya'), 'Merhaba dunya');
      expect(toAprsAscii('çğıöşü ÇĞİÖŞÜ'), 'cgiosu CGIOSU');
    });

    test('Polish and German letters', () {
      expect(toAprsAscii('żółć'), 'zolc');
      expect(toAprsAscii('Łódź, Kraków'), 'Lodz, Krakow');
      // ö and ü follow the Turkish mapping (o, u); ä and ß are German-only.
      expect(toAprsAscii('Grüße aus Köln, straße, Käse'), 'Grusse aus Koln, strasse, Kaese');
    });

    test('characters APRS messages must not contain are dropped', () {
      expect(toAprsAscii('a{b|c~d'), 'abcd');
    });

    test('emoji and other symbols are dropped, text around them is kept tidy', () {
      expect(toAprsAscii('tamam 👍 geliyorum'), 'tamam geliyorum');
      expect(toAprsAscii('ok 👍'), 'ok');
    });

    test('whitespace and control characters are collapsed', () {
      expect(toAprsAscii('  a \n\t b  '), 'a b');
      expect(toAprsAscii('a\u0007b'), 'ab');
    });

    test('is cut to the APRS limit without leaving a trailing space', () {
      final long = '${'a' * 66} bbbbbbbb';
      final out = toAprsAscii(long);
      expect(out.length, lessThanOrEqualTo(67));
      expect(out, isNot(endsWith(' ')));
      expect(out, startsWith('a' * 66));
    });

    test('empty and symbol-only input give an empty string', () {
      expect(toAprsAscii(''), '');
      expect(toAprsAscii('👍🙂'), '');
      expect(toAprsAscii('   '), '');
    });

    test('plain ASCII passes through unchanged', () {
      expect(toAprsAscii('QSL 73 de N0DEMO-9, 5/9!'), 'QSL 73 de N0DEMO-9, 5/9!');
    });
  });
}
