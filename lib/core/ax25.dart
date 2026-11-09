import 'dart:typed_data';
import '../l10n/app_strings.dart';

final RegExp _addressPattern = RegExp(r'^([A-Za-z0-9]{1,6})(?:-(\d{1,2}))?$');

/// An AX.25 address: callsign, SSID 0-15 and the "has been repeated" (H) flag.
class Ax25Address {
  const Ax25Address({required this.callsign, this.ssid = 0, this.repeated = false});

  final String callsign;
  final int ssid;
  final bool repeated;

  /// Parses `CALL`, `CALL-7` or `CALL-7*`. Throws [FormatException] if invalid.
  factory Ax25Address.parse(String text) {
    var value = text.trim();
    var repeated = false;
    if (value.endsWith('*')) {
      repeated = true;
      value = value.substring(0, value.length - 1);
    }
    final match = _addressPattern.firstMatch(value);
    if (match == null) throw FormatException(t('Geçersiz adres: "{text}"', {'text': text}));
    final ssid = match.group(2) == null ? 0 : int.parse(match.group(2)!);
    if (ssid > 15) throw FormatException(t('SSID 0-15 olmalı: "{text}"', {'text': text}));
    return Ax25Address(callsign: match.group(1)!.toUpperCase(), ssid: ssid, repeated: repeated);
  }

  /// Seven-byte wire form. [last] marks the final address of the header.
  List<int> encode({required bool last}) {
    final padded = callsign.padRight(6);
    return <int>[
      for (var i = 0; i < 6; i++) padded.codeUnitAt(i) << 1,
      0x60 | (ssid << 1) | (repeated ? 0x80 : 0) | (last ? 1 : 0),
    ];
  }

  @override
  String toString() => '$callsign${ssid > 0 ? '-$ssid' : ''}${repeated ? '*' : ''}';

  @override
  bool operator ==(Object other) =>
      other is Ax25Address && other.callsign == callsign && other.ssid == ssid && other.repeated == repeated;

  @override
  int get hashCode => Object.hash(callsign, ssid, repeated);
}

/// An AX.25 UI frame (control 0x03, PID 0xF0), which is what APRS uses.
class Ax25Frame {
  const Ax25Frame({
    required this.destination,
    required this.source,
    this.digipeaters = const <Ax25Address>[],
    required this.info,
  });

  static const int control = 0x03;
  static const int pid = 0xF0;
  static const int maxDigipeaters = 8;

  final Ax25Address destination;
  final Ax25Address source;
  final List<Ax25Address> digipeaters;
  final Uint8List info;

  Uint8List encode() {
    if (digipeaters.length > maxDigipeaters) {
      throw ArgumentError(t('En fazla {maxDigipeaters} digipeater olabilir.', {'maxDigipeaters': maxDigipeaters}));
    }
    final out = <int>[
      ...destination.encode(last: false),
      ...source.encode(last: digipeaters.isEmpty),
      for (var i = 0; i < digipeaters.length; i++) ...digipeaters[i].encode(last: i == digipeaters.length - 1),
      control,
      pid,
      ...info,
    ];
    return Uint8List.fromList(out);
  }

  /// Returns null when [data] is not a well-formed UI frame.
  static Ax25Frame? decode(Uint8List data) {
    if (data.length < 16) return null;
    final destination = _decodeAddress(data, 0, isDigipeater: false);
    final source = _decodeAddress(data, 7, isDigipeater: false);
    if (destination == null || source == null) return null;
    var last = data[13] & 1 == 1;
    var offset = 14;
    final digis = <Ax25Address>[];
    while (!last) {
      if (digis.length >= maxDigipeaters || offset + 7 + 2 > data.length) return null;
      final digi = _decodeAddress(data, offset, isDigipeater: true);
      if (digi == null) return null;
      digis.add(digi);
      last = data[offset + 6] & 1 == 1;
      offset += 7;
    }
    if (offset + 2 > data.length || data[offset] != control || data[offset + 1] != pid) return null;
    return Ax25Frame(
      destination: destination,
      source: source,
      digipeaters: List<Ax25Address>.unmodifiable(digis),
      info: Uint8List.fromList(data.sublist(offset + 2)),
    );
  }

  /// Bit 7 of the SSID byte is the H ("has been repeated") bit only for
  /// digipeaters; for destination and source it is the AX.25 v2 command bit.
  static Ax25Address? _decodeAddress(Uint8List d, int o, {required bool isDigipeater}) {
    final chars = <int>[for (var i = 0; i < 6; i++) d[o + i] >> 1];
    final call = String.fromCharCodes(chars).trimRight();
    if (call.isEmpty || chars.any((c) => c < 0x20 || c > 0x7E)) return null;
    final flags = d[o + 6];
    return Ax25Address(callsign: call, ssid: (flags >> 1) & 0x0F, repeated: isDigipeater && flags & 0x80 != 0);
  }

  /// APRS-IS / TNC2 text form: `SRC>DST,DIGI*:info`.
  String toTnc2() {
    final path = <Ax25Address>[destination, ...digipeaters].join(',');
    return '$source>$path:${String.fromCharCodes(info)}';
  }
}
