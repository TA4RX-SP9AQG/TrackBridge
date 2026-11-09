import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/l10n/app_strings.dart';
import 'package:trackbridge/l10n/english.dart';

void main() {
  tearDown(() => L10n.setLanguage(AppLanguage.turkish));

  test('Turkish is the default and returns the source text unchanged', () {
    L10n.setLanguage(AppLanguage.turkish);
    expect(t('Ayarlar'), 'Ayarlar');
  });

  test('English returns the translation, and falls back to the Turkish text when none exists', () {
    L10n.setLanguage(AppLanguage.english);
    expect(t('Ayarlar'), 'Settings');
    expect(t('Bu metin için çeviri yok 12345'), 'Bu metin için çeviri yok 12345');
  });

  test('placeholders are filled in both languages', () {
    L10n.setLanguage(AppLanguage.turkish);
    expect(t('{n} paket · telsizle duyulanlar', {'n': 5}), '5 paket · telsizle duyulanlar');
    L10n.setLanguage(AppLanguage.english);
    expect(t('{n} paket · telsizle duyulanlar', {'n': 5}), '5 packets · heard over the radio');
  });

  test('a missing argument leaves the placeholder visible instead of crashing', () {
    expect(t('{n} paket · telsizle duyulanlar', {}), '{n} paket · telsizle duyulanlar');
  });

  test('system language: Turkish phones get Turkish, everything else English', () {
    expect(AppLanguage.fromSystem('tr'), AppLanguage.turkish);
    expect(AppLanguage.fromSystem('en'), AppLanguage.english);
    expect(AppLanguage.fromSystem('pl'), AppLanguage.english);
    expect(AppLanguage.fromSystem(null), AppLanguage.english);
  });

  test('the stored preference maps to a language (system = follow the phone)', () {
    expect(AppLanguage.resolve('tr', 'en'), AppLanguage.turkish);
    expect(AppLanguage.resolve('en', 'tr'), AppLanguage.english);
    expect(AppLanguage.resolve('system', 'tr'), AppLanguage.turkish);
    expect(AppLanguage.resolve('system', 'de'), AppLanguage.english);
    expect(AppLanguage.resolve('garbage', 'tr'), AppLanguage.turkish);
  });

  group('English catalog quality', () {
    test('no empty translations', () {
      for (final e in englishStrings.entries) {
        expect(e.value.trim(), isNotEmpty, reason: e.key);
      }
    });

    test('every translation has exactly the same placeholders as its source', () {
      final re = RegExp(r'\{(\w+)\}');
      for (final e in englishStrings.entries) {
        final a = re.allMatches(e.key).map((m) => m.group(1)).toSet();
        final b = re.allMatches(e.value).map((m) => m.group(1)).toSet();
        expect(b, a, reason: e.key);
      }
    });

    test('translations contain no Turkish-only letters (catches untranslated leftovers)', () {
      final turkish = RegExp(r'[çğıöşüÇĞİÖŞÜ]');
      for (final e in englishStrings.entries) {
        expect(turkish.hasMatch(e.value), isFalse, reason: '${e.key} -> ${e.value}');
      }
    });
  });
}
