import 'aprs.dart';
import 'ax25.dart';

/// `<NAME:length>value`. Empty values produce no field.
String adifField(String name, String value) => value.isEmpty ? '' : '<$name:${value.length}>$value';

/// Amateur radio band for [freqMhz] (ADIF band names), or '' when it is outside the ham bands.
String adifBand(double freqMhz) {
  const bands = <(String, double, double)>[
    ('160m', 1.8, 2.0), ('80m', 3.5, 4.0), ('60m', 5.06, 5.45), ('40m', 7.0, 7.3), ('30m', 10.1, 10.15),
    ('20m', 14.0, 14.35), ('17m', 18.068, 18.168), ('15m', 21.0, 21.45), ('12m', 24.89, 24.99), ('10m', 28.0, 29.7),
    ('6m', 50.0, 54.0), ('4m', 70.0, 71.0), ('2m', 144.0, 148.0), ('1.25m', 222.0, 225.0), ('70cm', 420.0, 450.0),
    ('33cm', 902.0, 928.0), ('23cm', 1240.0, 1300.0), ('13cm', 2300.0, 2450.0),
  ];
  // 868 MHz (the European LoRa band) has no ham allocation but Wavelog accepts the closest ADIF name.
  if (freqMhz >= 863 && freqMhz <= 870) return '33cm';
  for (final (name, lo, hi) in bands) {
    if (freqMhz >= lo && freqMhz <= hi) return name;
  }
  return '';
}

String _asciiOnly(String s) {
  final out = StringBuffer();
  for (final c in s.runes) {
    if (c >= 0x20 && c < 0x7F && c != 0x3C && c != 0x3E) out.writeCharCode(c); // no '<' or '>'
  }
  return out.toString().trim();
}

String _baseCall(String call, String what) {
  final trimmed = call.trim();
  if (!isUsableCallsign(trimmed.isEmpty ? '' : trimmed.replaceAll('*', ''))) {
    throw FormatException('Geçersiz $what: "$call"');
  }
  return Ax25Address.parse(trimmed).callsign;
}

/// One ADIF QSO record for a packet-radio (APRS) contact. Callsigns lose their SSID, the time is
/// written in UTC and the comment is reduced to safe ASCII.
String buildAdifRecord({
  required String call,
  required String myCall,
  required DateTime timeUtc,
  required double freqMhz,
  String comment = '',
}) {
  final other = _baseCall(call, 'çağrı işareti');
  final mine = _baseCall(myCall, 'kendi çağrı işaretiniz');
  final t = timeUtc.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final date = '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}';
  final time = '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  final freq = freqMhz.toStringAsFixed(3);
  return [
    adifField('CALL', other),
    adifField('STATION_CALLSIGN', mine),
    adifField('QSO_DATE', date),
    adifField('TIME_ON', time),
    adifField('MODE', 'PKT'),
    adifField('FREQ', freq),
    adifField('BAND', adifBand(freqMhz)),
    adifField('COMMENT', _asciiOnly(comment)),
    '<EOR>',
  ].join();
}
