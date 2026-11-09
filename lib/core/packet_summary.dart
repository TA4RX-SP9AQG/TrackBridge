import '../l10n/app_strings.dart';

enum PacketKind { position, message, status, other }

/// A heard TNC2 line split into the parts a list row needs.
class PacketSummary {
  const PacketSummary({required this.source, required this.kind, required this.text, required this.viaDigipeater});

  final String source;
  final PacketKind kind;

  /// Human readable body (messages are shown as "→ ADDRESSEE: text").
  final String text;

  /// True when a digipeater has already repeated the packet (`CALL*` in the path).
  final bool viaDigipeater;
}

final RegExp _ack = RegExp(r'^(ack|rej)(\w{1,5})$');

/// Splits `SRC>DST,PATH:info` and classifies the info field. Never throws.
PacketSummary summarizePacket(String tnc2) {
  final colon = tnc2.indexOf(':');
  final header = colon < 0 ? tnc2 : tnc2.substring(0, colon);
  final info = colon < 0 ? '' : tnc2.substring(colon + 1);
  final gt = header.indexOf('>');
  final source = gt < 0 ? header : header.substring(0, gt);
  final path = gt < 0 ? '' : header.substring(gt + 1);
  final via = path.split(',').skip(1).any((h) => h.endsWith('*'));
  if (info.isEmpty) {
    return PacketSummary(source: source, kind: PacketKind.other, text: '', viaDigipeater: via);
  }
  final type = info[0];
  if (type == ':' && info.length >= 11 && info[10] == ':') {
    final to = info.substring(1, 10).trim();
    var body = info.substring(11);
    final ack = _ack.firstMatch(body);
    if (ack != null) {
      body = ack.group(1) == 'ack' ? t('onay (ack {v1})', {'v1': ack.group(2)}) : t('ret (rej {v1})', {'v1': ack.group(2)});
    } else {
      final brace = body.lastIndexOf('{');
      if (brace >= 0) body = body.substring(0, brace);
    }
    return PacketSummary(source: source, kind: PacketKind.message, text: '→ $to: $body', viaDigipeater: via);
  }
  if ('!=/@;)`\''.contains(type)) {
    return PacketSummary(source: source, kind: PacketKind.position, text: info, viaDigipeater: via);
  }
  if (type == '>') {
    return PacketSummary(source: source, kind: PacketKind.status, text: info.substring(1), viaDigipeater: via);
  }
  return PacketSummary(source: source, kind: PacketKind.other, text: info, viaDigipeater: via);
}
