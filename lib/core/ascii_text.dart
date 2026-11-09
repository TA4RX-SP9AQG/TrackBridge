import 'aprs.dart';

const Map<String, String> _replacements = {
  // Turkish
  'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I', 'ö': 'o', 'Ö': 'O', 'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U',
  // Polish
  'ą': 'a', 'Ą': 'A', 'ć': 'c', 'Ć': 'C', 'ę': 'e', 'Ę': 'E', 'ł': 'l', 'Ł': 'L', 'ń': 'n', 'Ń': 'N', 'ó': 'o', 'Ó': 'O',
  'ś': 's', 'Ś': 'S', 'ź': 'z', 'Ź': 'Z', 'ż': 'z', 'Ż': 'Z',
  // German (ö and ü share the Turkish mapping above; ä and ß are extra)
  'ä': 'ae', 'Ä': 'Ae', 'ß': 'ss',
};

/// Characters that must not appear inside an APRS message body.
const String _forbidden = '{|~';

/// Turns free text (for example a voice transcription) into something an APRS
/// message can carry: transliterates Turkish, Polish and German letters, drops
/// everything that is not printable ASCII, collapses whitespace and cuts the
/// result to [kMaxMessageLength] characters.
String toAprsAscii(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = _replacements[ch];
    if (mapped != null) {
      out.write(mapped);
    } else if (rune == 0x09 || rune == 0x0A || rune == 0x0D || rune == 0x20) {
      out.write(' ');
    } else if (rune > 0x20 && rune < 0x7F && !_forbidden.contains(ch)) {
      out.write(ch);
    }
  }
  var text = out.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  if (text.length > kMaxMessageLength) text = text.substring(0, kMaxMessageLength).trimRight();
  return text;
}
