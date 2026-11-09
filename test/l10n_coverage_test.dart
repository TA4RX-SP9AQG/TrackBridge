import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/l10n/english.dart';

/// Every `t('...')` call in lib/ must have an English entry, and every entry must still be used.
void main() {
  final call = RegExp(r"""(?<![\w$.])t\(\s*((?:'(?:\\.|[^'\\\n])*'\s*)+)""");
  final literal = RegExp(r"""'((?:\\.|[^'\\\n])*)'""");
  final escape = RegExp(r'\\(.)');

  String unescape(String s) => s.replaceAllMapped(escape, (m) => m[1] == 'n' ? '\n' : m[1]!);

  // Translated through a variable (t(label)), so the scan above cannot see them.
  const indirect = {
    'Acil durum ve hizmetler', 'Araç', 'Araçlar', 'Bisiklet', 'Diğer', 'Hava durumu', 'Yerler ve işaretler',
    'Yürüyüş', 'Telsiz ve istasyonlar', 'Kişiler ve hayvanlar',
  };

  Set<String> usedKeys() {
    final keys = <String>{...indirect};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart') || path.contains('lib/l10n/')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        keys.add(literal.allMatches(m[1]!).map((l) => unescape(l[1]!)).join());
      }
    }
    return keys;
  }

  test('every translated text used in the app has an English entry', () {
    final missing = usedKeys().where((k) => !englishStrings.containsKey(k)).toList()..sort();
    expect(missing, isEmpty, reason: 'add these to lib/l10n/english.dart');
  });

  test('no English entry is left over after its Turkish text was removed from the code', () {
    final used = usedKeys();
    final unused = englishStrings.keys.where((k) => !used.contains(k)).toList()..sort();
    expect(unused, isEmpty, reason: 'remove these from lib/l10n/english.dart');
  });
}
