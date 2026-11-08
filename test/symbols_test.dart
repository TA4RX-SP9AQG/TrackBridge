import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/symbols.dart';

void main() {
  group('catalog', () {
    test('each table has all 94 printable codes exactly once', () {
      for (final table in [primarySymbols, alternateSymbols]) {
        expect(table, hasLength(94));
        final codes = table.map((s) => s.code).toList();
        expect(codes.toSet(), hasLength(94));
        expect(codes.first, '!');
        expect(codes.last, '~');
        for (var c = 0x21; c <= 0x7E; c++) {
          expect(codes, contains(String.fromCharCode(c)));
        }
      }
    });

    test('tables are tagged and names are present', () {
      expect(primarySymbols.every((s) => s.table == '/'), isTrue);
      expect(alternateSymbols.every((s) => s.table == r'\'), isTrue);
      expect(primarySymbols.every((s) => s.name.trim().isNotEmpty), isTrue);
      expect(alternateSymbols.every((s) => s.name.trim().isNotEmpty), isTrue);
    });

    test('well known symbols', () {
      expect(lookupSymbol('/', '-')!.name, contains('House'));
      expect(lookupSymbol('/', '>')!.name, 'Car');
      expect(lookupSymbol('/', '#')!.name, contains('Digipeater'));
      expect(lookupSymbol('/', '_')!.category, SymbolCategory.weather);
      expect(lookupSymbol('/', 'b')!.name, 'Bicycle');
      expect(lookupSymbol(r'\', '#')!.name, contains('Digipeater'));
      expect(lookupSymbol(r'\', '&')!.name, contains('Gateway'));
    });

    test('lookup rejects bad codes', () {
      expect(lookupSymbol('/', ' '), isNull);
      expect(lookupSymbol('/', 'ab'), isNull);
      expect(lookupSymbol('/', 'ş'), isNull);
    });

    test('reserved entries are flagged so the picker can hide them', () {
      final reservedPrimary = primarySymbols.where((s) => s.reserved).map((s) => s.code).toSet();
      expect(reservedPrimary, containsAll(['"', 'D', 'J', '{', '}']));
      expect(lookupSymbol('/', '-')!.reserved, isFalse);
      expect(selectableSymbols(primarySymbols).any((s) => s.reserved), isFalse);
    });
  });

  group('table character', () {
    test('slash is primary, backslash is alternate without overlay', () {
      final p = resolveSymbol('/', '-')!;
      expect((p.info.table, p.overlay), ('/', null));
      final a = resolveSymbol(r'\', '#')!;
      expect((a.info.table, a.overlay), (r'\', null));
    });

    test('digit or capital letter means alternate table with that overlay', () {
      final r = resolveSymbol('S', '#')!;
      expect((r.info.table, r.info.code, r.overlay), (r'\', '#', 'S'));
      expect(resolveSymbol('7', '&')!.overlay, '7');
    });

    test('invalid table characters resolve to null', () {
      for (final c in ['a', '@', ' ', '', 'ab', '|']) {
        expect(resolveSymbol(c, '-'), isNull, reason: 'table "$c"');
      }
    });

    test('tableCharIsValid agrees with resolveSymbol', () {
      expect(tableCharIsValid('/'), isTrue);
      expect(tableCharIsValid(r'\'), isTrue);
      expect(tableCharIsValid('Z'), isTrue);
      expect(tableCharIsValid('z'), isFalse);
    });
  });

  group('sprite cells', () {
    test('cell index is code minus 0x21 on a 16 column grid', () {
      expect(spriteCell('!'), (col: 0, row: 0));
      expect(spriteCell('0'), (col: 15, row: 0)); // matches the real sheet: digit zero is the last tile of row 0
      expect(spriteCell('1'), (col: 0, row: 1));
      expect(spriteCell('A'), (col: 0, row: 2));
      expect(spriteCell('~'), (col: 13, row: 5));
    });

    test('out of range codes have no cell', () {
      expect(spriteCell(' '), isNull);
      expect(spriteCell('\u007f'), isNull);
      expect(spriteCell(''), isNull);
    });
  });

  group('overlay and search', () {
    test('overlay capable alternate symbols', () {
      expect(lookupSymbol(r'\', '#')!.acceptsOverlay, isTrue);
      expect(lookupSymbol(r'\', '&')!.acceptsOverlay, isTrue);
      expect(lookupSymbol(r'\', '>')!.acceptsOverlay, isTrue);
      expect(lookupSymbol(r'\', '!')!.acceptsOverlay, isFalse);
      expect(lookupSymbol('/', '-')!.acceptsOverlay, isFalse);
    });

    test('search is case insensitive and matches name or code', () {
      expect(searchSymbols(primarySymbols, 'digi').map((s) => s.code), contains('#'));
      expect(searchSymbols(primarySymbols, 'BICYCLE').map((s) => s.code), ['b']);
      expect(searchSymbols(primarySymbols, '').length, selectableSymbols(primarySymbols).length);
      expect(searchSymbols(primarySymbols, 'zzzz-no-such'), isEmpty);
    });

    test('search can be limited to a category', () {
      final weather = searchSymbols(alternateSymbols, '', category: SymbolCategory.weather);
      expect(weather, isNotEmpty);
      expect(weather.every((s) => s.category == SymbolCategory.weather), isTrue);
    });
  });
}
