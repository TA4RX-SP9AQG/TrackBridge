import 'english.dart';

/// Interface languages.
enum AppLanguage {
  turkish,
  english;

  /// Turkish phones get Turkish; every other system language gets English.
  static AppLanguage fromSystem(String? languageCode) => languageCode == 'tr' ? turkish : english;

  /// [preference] is the stored setting: `tr`, `en` or `system` (follow the phone).
  static AppLanguage resolve(String preference, String? systemLanguageCode) => switch (preference) {
        'tr' => turkish,
        'en' => english,
        _ => fromSystem(systemLanguageCode),
      };
}

/// Holds the current interface language. The source text of the app is Turkish; English comes from
/// [englishStrings], keyed by the Turkish text. A missing translation falls back to the Turkish text,
/// so a gap is visible but never breaks anything.
class L10n {
  const L10n._();

  static AppLanguage _language = AppLanguage.turkish;

  static AppLanguage get language => _language;

  static void setLanguage(AppLanguage value) => _language = value;
}

/// Translates [turkish] into the current language and fills `{name}` placeholders from [args].
String t(String turkish, [Map<String, Object?> args = const <String, Object?>{}]) {
  var text = L10n.language == AppLanguage.english ? (englishStrings[turkish] ?? turkish) : turkish;
  if (args.isNotEmpty) {
    for (final e in args.entries) {
      text = text.replaceAll('{${e.key}}', '${e.value}');
    }
  }
  return text;
}
