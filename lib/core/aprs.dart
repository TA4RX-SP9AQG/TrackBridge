import 'ax25.dart';
import '../l10n/app_strings.dart';

/// Destination ("tocall") used for packets we build. The tracker firmware uses
/// the same value. TODO(release): request an own tocall before a store release.
const String kDefaultTocall = 'APLRT1';

/// APRS message text limit.
const int kMaxMessageLength = 67;

/// APRS position comment limit.
const int kMaxCommentLength = 43;

enum AprsMessageKind { message, ack, rej }

class AprsMessage {
  const AprsMessage({
    required this.kind,
    required this.addressee,
    required this.text,
    this.id,
    this.replyAckId,
  });

  final AprsMessageKind kind;
  final String addressee;

  /// Message text; empty for ack/rej.
  final String text;

  /// Message number; for ack/rej the number being acknowledged/rejected.
  final String? id;

  /// APRS 1.1 reply-ack (`text{MM}AA`): the sender also acknowledges our
  /// message number AA.
  final String? replyAckId;
}

final RegExp _idWithReplyAck = RegExp(r'^([A-Za-z0-9]{1,5})(?:\}([A-Za-z0-9]{0,5}))?$');

final RegExp _idPattern = RegExp(r'^[A-Za-z0-9]{1,5}$');

bool _isPrintableAscii(String s) => s.codeUnits.every((c) => c >= 0x20 && c <= 0x7E);

String _paddedAddressee(String to) {
  final value = to.trim().toUpperCase();
  if (value.isEmpty || value.length > 9 || value.contains(':')) {
    throw FormatException(t('Geçersiz alıcı: "{to}"', {'to': to}));
  }
  return value.padRight(9);
}

/// Builds the information field of an APRS message: `:ADDRESSEE:text{id`.
String buildMessageInfo({required String to, required String text, String? id}) {
  if (text.isEmpty) throw FormatException(t('Mesaj boş olamaz.'));
  if (text.length > kMaxMessageLength) {
    throw const FormatException('Mesaj en fazla $kMaxMessageLength karakter olabilir.');
  }
  if (!_isPrintableAscii(text) || text.contains('{') || text.contains('|') || text.contains('~')) {
    throw FormatException(t('Mesaj yalnızca ASCII olmalı ({, | ve ~ kullanılamaz).'));
  }
  if (id != null && !_idPattern.hasMatch(id)) {
    throw FormatException(t('Mesaj numarası 1-5 harf/rakam olmalı.'));
  }
  return ':${_paddedAddressee(to)}:$text${id == null ? '' : '{$id'}';
}

/// Builds an acknowledgement for message [id] sent by [to].
String buildAckInfo({required String to, required String id}) {
  if (!_idPattern.hasMatch(id)) throw FormatException(t('Geçersiz mesaj numarası.'));
  return ':${_paddedAddressee(to)}:ack$id';
}

/// Parses the information field of an APRS message packet, or returns null.
AprsMessage? parseMessage(String info) {
  if (info.length < 11 || info[0] != ':' || info[10] != ':') return null;
  final addressee = info.substring(1, 10).trimRight();
  if (addressee.isEmpty) return null;
  final body = info.substring(11);
  for (final entry in {'ack': AprsMessageKind.ack, 'rej': AprsMessageKind.rej}.entries) {
    if (body.startsWith(entry.key) && body.length > entry.key.length) {
      var id = body.substring(entry.key.length);
      final brace = id.indexOf('}'); // reply-ack form "ack12}34": keep the first id
      if (brace >= 0) id = id.substring(0, brace);
      if (_idPattern.hasMatch(id)) {
        return AprsMessage(kind: entry.value, addressee: addressee, text: '', id: id);
      }
    }
  }
  final brace = body.lastIndexOf('{');
  if (brace >= 0) {
    final match = _idWithReplyAck.firstMatch(body.substring(brace + 1));
    if (match != null) {
      final reply = match.group(2);
      return AprsMessage(
        kind: AprsMessageKind.message,
        addressee: addressee,
        text: body.substring(0, brace),
        id: match.group(1),
        replyAckId: (reply == null || reply.isEmpty) ? null : reply,
      );
    }
  }
  return AprsMessage(kind: AprsMessageKind.message, addressee: addressee, text: body);
}

/// Builds an uncompressed position report: `!DDMM.hhN/DDDMM.hhE>comment`.
///
/// Values are truncated, not rounded. [ambiguity] 0-4 replaces that many
/// digits (from the right) with spaces, so the hidden digits are never sent.
String buildPositionInfo({
  required double lat,
  required double lon,
  required String symbolTable,
  required String symbol,
  String comment = '',
  int ambiguity = 0,
}) {
  if (lat.isNaN || lat < -90 || lat > 90) throw FormatException(t('Enlem -90..90 olmalı.'));
  if (lon.isNaN || lon < -180 || lon > 180) throw FormatException(t('Boylam -180..180 olmalı.'));
  if (ambiguity < 0 || ambiguity > 4) throw FormatException(t('Belirsizlik 0-4 olmalı.'));
  if (symbolTable.length != 1 || symbol.length != 1) throw FormatException(t('Sembol tek karakter olmalı.'));
  if (comment.length > kMaxCommentLength || !_isPrintableAscii(comment) || comment.contains('|') || comment.contains('~')) {
    throw FormatException(t('Yorum ASCII ve en fazla {kMaxCommentLength} karakter olmalı.', {'kMaxCommentLength': kMaxCommentLength}));
  }
  final latText = _blank(_degMin(lat.abs(), 2), 2, ambiguity);
  final lonText = _blank(_degMin(lon.abs(), 3), 3, ambiguity);
  return '!$latText${lat >= 0 ? 'N' : 'S'}$symbolTable$lonText${lon >= 0 ? 'E' : 'W'}$symbol$comment';
}

String _degMin(double value, int degreeDigits) {
  final hundredths = (value * 6000 + 1e-6).floor(); // 1/100 minute units, truncated
  final degrees = hundredths ~/ 6000;
  final rest = hundredths % 6000;
  final minutes = (rest ~/ 100).toString().padLeft(2, '0');
  final fraction = (rest % 100).toString().padLeft(2, '0');
  return '${degrees.toString().padLeft(degreeDigits, '0')}$minutes.$fraction';
}

String _blank(String text, int degreeDigits, int ambiguity) {
  if (ambiguity == 0) return text;
  final chars = text.split('');
  var remaining = ambiguity;
  for (var i = chars.length - 1; i >= degreeDigits && remaining > 0; i--) {
    if (chars[i] == '.') continue;
    chars[i] = ' ';
    remaining--;
  }
  return chars.join();
}

/// `ta4rx-0` -> `TA4RX`, `TA4RX-7*` -> `TA4RX-7`. Throws [FormatException] if invalid.
String normalizeCallsign(String value) {
  final a = Ax25Address.parse(value);
  return Ax25Address(callsign: a.callsign, ssid: a.ssid).toString();
}

const Set<String> _placeholderCalls = {'N0CALL', 'NOCALL', 'MYCALL'};

/// True when [value] is a valid `CALL[-SSID]` and not a well-known placeholder.
bool isUsableCallsign(String value) {
  try {
    final address = Ax25Address.parse(value);
    return !_placeholderCalls.contains(address.callsign) && !address.repeated;
  } on FormatException {
    return false;
  }
}
