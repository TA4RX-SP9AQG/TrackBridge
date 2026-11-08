import 'ax25.dart';

/// Position encodings found in APRS packets.
enum PositionFormat { uncompressed, compressed, micE }

/// A position decoded from an APRS packet (station, object or item).
class AprsPosition {
  const AprsPosition({
    required this.lat,
    required this.lon,
    required this.symbolTable,
    required this.symbolCode,
    required this.format,
    this.comment = '',
    this.speedKmh,
    this.courseDeg,
    this.altitudeM,
    this.ambiguity = 0,
    this.objectName,
    this.killed = false,
  });

  final double lat;
  final double lon;

  /// `/`, `\`, or an overlay character (as sent; compressed `a`-`j` already mapped to `0`-`9`).
  final String symbolTable;
  final String symbolCode;
  final PositionFormat format;

  /// Free text, without the course/speed and altitude fields that were decoded.
  final String comment;
  final double? speedKmh;

  /// Degrees 1-360, null when unknown.
  final int? courseDeg;
  final double? altitudeM;

  /// 0-4 blanked digits; lat/lon are the centre of that square.
  final int ambiguity;

  /// Set for objects and items: their name replaces the sender as the identity.
  final String? objectName;

  /// An object/item that its owner has deleted.
  final bool killed;
}

const double _knotsToKmh = 1.852;
const double _feetToMeters = 0.3048;

/// Parses the position, if any, from [frame].
AprsPosition? parsePositionFrame(Ax25Frame frame) =>
    parsePosition(destination: frame.destination.callsign, info: String.fromCharCodes(frame.info));

/// Parses the position from an APRS information field. [destination] is the
/// destination callsign without SSID (Mic-E positions live partly in it).
/// Returns null for anything that is not a well-formed position report.
AprsPosition? parsePosition({required String destination, required String info}) {
  if (info.isEmpty) return null;
  final type = info.codeUnitAt(0);
  switch (String.fromCharCode(type)) {
    case '!':
    case '=':
      return _parseBody(info.substring(1));
    case '/':
    case '@':
      return info.length < 8 ? null : _parseBody(info.substring(8)); // skip the 7 character timestamp
    case ';':
      return _parseObject(info);
    case ')':
      return _parseItem(info);
    case '`':
    case "'":
      return _parseMicE(destination, info);
  }
  if (type == 0x1C || type == 0x1D) return _parseMicE(destination, info);
  return null;
}

// ---- objects and items ----

AprsPosition? _parseObject(String info) {
  if (info.length < 19) return null;
  final state = info[10];
  if (state != '*' && state != '_') return null;
  final name = info.substring(1, 10).trimRight();
  if (name.isEmpty) return null;
  return _parseBody(info.substring(18), objectName: name, killed: state == '_');
}

AprsPosition? _parseItem(String info) {
  for (var i = 4; i <= 10 && i < info.length; i++) {
    final c = info[i];
    if (c == '!' || c == '_') {
      return _parseBody(info.substring(i + 1), objectName: info.substring(1, i), killed: c == '_');
    }
  }
  return null;
}

// ---- uncompressed and compressed ----

AprsPosition? _parseBody(String body, {String? objectName, bool killed = false}) {
  if (body.isEmpty) return null;
  final first = body.codeUnitAt(0);
  final startsWithDigit = (first >= 0x30 && first <= 0x39) || first == 0x20;
  return startsWithDigit
      ? _parseUncompressed(body, objectName, killed)
      : _parseCompressed(body, objectName, killed);
}

AprsPosition? _parseUncompressed(String body, String? objectName, bool killed) {
  if (body.length < 19) return null;
  final latText = body.substring(0, 8);
  final lonText = body.substring(9, 18);
  final latNs = latText[7];
  final lonEw = lonText[8];
  if ((latNs != 'N' && latNs != 'S') || (lonEw != 'E' && lonEw != 'W')) return null;
  if (latText[4] != '.' || lonText[5] != '.') return null;

  final ambiguity = _countBlanks(latText, const [6, 5, 3, 2]);
  if (ambiguity < 0) return null;
  final latDeg = _digits(latText.substring(0, 2));
  final latMin = _minutes(latText.substring(2, 4), latText.substring(5, 7));
  final lonDeg = _digits(lonText.substring(0, 3));
  final lonMin = _minutes(lonText.substring(3, 5), lonText.substring(6, 8));
  if (latDeg == null || latMin == null || lonDeg == null || lonMin == null) return null;

  final centre = _centreOffsetMinutes(ambiguity);
  var lat = latDeg + (latMin + centre) / 60;
  var lon = lonDeg + (lonMin + centre) / 60;
  if (latNs == 'S') lat = -lat;
  if (lonEw == 'W') lon = -lon;
  if (!_inRange(lat, lon)) return null;

  final extras = _extractExtras(body.substring(19), withExtension: true);
  return AprsPosition(
    lat: lat,
    lon: lon,
    symbolTable: body[8],
    symbolCode: body[18],
    format: PositionFormat.uncompressed,
    comment: extras.comment,
    speedKmh: extras.speedKmh,
    courseDeg: extras.courseDeg,
    altitudeM: extras.altitudeM,
    ambiguity: ambiguity,
    objectName: objectName,
    killed: killed,
  );
}

AprsPosition? _parseCompressed(String body, String? objectName, bool killed) {
  if (body.length < 13) return null;
  final latValue = _base91(body.substring(1, 5));
  final lonValue = _base91(body.substring(5, 9));
  if (latValue == null || lonValue == null) return null;
  final lat = 90 - latValue / 380926;
  final lon = -180 + lonValue / 190463;
  if (!_inRange(lat, lon)) return null;

  var table = body[0];
  final tableUnit = table.codeUnitAt(0);
  if (tableUnit >= 0x61 && tableUnit <= 0x6A) table = String.fromCharCode(0x30 + tableUnit - 0x61); // a-j -> 0-9
  if (!(table == '/' || table == r'\' || (tableUnit >= 0x41 && tableUnit <= 0x5A) || (tableUnit >= 0x30 && tableUnit <= 0x39) || (tableUnit >= 0x61 && tableUnit <= 0x6A))) {
    return null;
  }

  int? course;
  double? speedKmh;
  double? altitudeM;
  final c = body.codeUnitAt(10);
  final s = body.codeUnitAt(11);
  final typeByte = body.codeUnitAt(12) - 33;
  if (c != 0x20 && c >= 33 && c <= 122 && s >= 33 && s <= 122) {
    if ((typeByte & 0x18) == 0x10) {
      altitudeM = _pow(1.002, (c - 33) * 91 + (s - 33)) * _feetToMeters; // GGA altitude in feet
    } else {
      final deg = (c - 33) * 4;
      course = deg == 0 ? null : deg;
      final knots = _pow(1.08, s - 33) - 1;
      speedKmh = knots <= 0 ? null : knots * _knotsToKmh;
    }
  }

  final extras = _extractExtras(body.substring(13), withExtension: false);
  return AprsPosition(
    lat: lat,
    lon: lon,
    symbolTable: table,
    symbolCode: body[9],
    format: PositionFormat.compressed,
    comment: extras.comment,
    speedKmh: speedKmh,
    courseDeg: course,
    altitudeM: altitudeM ?? extras.altitudeM,
    objectName: objectName,
    killed: killed,
  );
}

// ---- Mic-E ----

AprsPosition? _parseMicE(String destination, String info) {
  if (destination.length < 6 || info.length < 9) return null;

  final digits = <int>[];
  var north = false;
  var lonOffset = false;
  var west = false;
  for (var i = 0; i < 6; i++) {
    final u = destination.codeUnitAt(i);
    int digit;
    var high = false; // P-Z: the "1" flag
    if (u >= 0x30 && u <= 0x39) {
      digit = u - 0x30;
    } else if (u >= 0x41 && u <= 0x4A && i < 3) {
      digit = u - 0x41; // A-J: custom message bit, positions 1-3 only
    } else if (u == 0x4B && i < 3) {
      digit = 0; // K: blank
    } else if (u == 0x4C) {
      digit = 0; // L: blank (flag 0)
    } else if (u >= 0x50 && u <= 0x59) {
      digit = u - 0x50;
      high = true;
    } else if (u == 0x5A) {
      digit = 0; // Z: blank (flag 1)
      high = true;
    } else {
      return null;
    }
    digits.add(digit);
    if (i == 3) north = high;
    if (i == 4) lonOffset = high;
    if (i == 5) west = high;
  }

  var ambiguity = 0;
  for (final i in const [5, 4, 3, 2]) {
    final u = destination.codeUnitAt(i);
    if (u == 0x4C || u == 0x5A || u == 0x4B) {
      ambiguity++;
    } else {
      break;
    }
  }

  final latMinutes = digits[2] * 10 + digits[3] + (digits[4] * 10 + digits[5]) / 100;
  var lat = digits[0] * 10 + digits[1] + (latMinutes + _centreOffsetMinutes(ambiguity)) / 60;
  if (!north) lat = -lat;

  var lonDeg = info.codeUnitAt(1) - 28;
  if (lonOffset) lonDeg += 100;
  if (lonDeg >= 190) {
    lonDeg -= 190;
  } else if (lonDeg >= 180) {
    lonDeg -= 80;
  }
  var lonMin = info.codeUnitAt(2) - 28;
  if (lonMin >= 60) lonMin -= 60;
  final lonHundredths = info.codeUnitAt(3) - 28;
  if (lonDeg < 0 || lonDeg > 179 || lonMin < 0 || lonMin > 59 || lonHundredths < 0 || lonHundredths > 99) return null;
  var lon = lonDeg + (lonMin + lonHundredths / 100) / 60;
  if (west) lon = -lon;
  if (!_inRange(lat, lon)) return null;

  final sp = info.codeUnitAt(4) - 28;
  final dc = info.codeUnitAt(5) - 28;
  final se = info.codeUnitAt(6) - 28;
  if (sp < 0 || dc < 0 || se < 0) return null;
  var speedKnots = sp * 10 + dc ~/ 10;
  var course = (dc % 10) * 100 + se;
  if (speedKnots >= 800) speedKnots -= 800;
  if (course >= 400) course -= 400;

  var rest = info.substring(9);
  if (rest.isNotEmpty && (rest[0] == '>' || rest[0] == ']' || rest[0] == '`' || rest[0] == "'")) {
    rest = rest.substring(1); // device type character
  }
  final altitude = RegExp(r'([!-{]{3})\}').firstMatch(rest);
  double? altitudeM;
  if (altitude != null) {
    final a = altitude.group(1)!;
    altitudeM = ((a.codeUnitAt(0) - 33) * 8281 + (a.codeUnitAt(1) - 33) * 91 + (a.codeUnitAt(2) - 33) - 10000).toDouble();
    rest = rest.replaceRange(altitude.start, altitude.end, '');
  }

  return AprsPosition(
    lat: lat,
    lon: lon,
    symbolTable: info[8],
    symbolCode: info[7],
    format: PositionFormat.micE,
    comment: rest.trim(),
    speedKmh: speedKnots > 0 ? speedKnots * _knotsToKmh : null,
    courseDeg: course >= 1 && course <= 360 ? course : null,
    altitudeM: altitudeM,
    ambiguity: ambiguity,
  );
}

// ---- helpers ----

class _Extras {
  const _Extras(this.comment, {this.speedKmh, this.courseDeg, this.altitudeM});

  final String comment;
  final double? speedKmh;
  final int? courseDeg;
  final double? altitudeM;
}

final RegExp _courseSpeed = RegExp(r'^(\d{3})/(\d{3})');
final RegExp _altitudeFeet = RegExp(r'/A=(-?\d{6})');

_Extras _extractExtras(String rest, {required bool withExtension}) {
  var text = rest;
  int? course;
  double? speed;
  if (withExtension) {
    final m = _courseSpeed.firstMatch(text);
    if (m != null) {
      final c = int.parse(m.group(1)!);
      final s = int.parse(m.group(2)!);
      course = c >= 1 && c <= 360 ? c : null;
      speed = s > 0 ? s * _knotsToKmh : null;
      text = text.substring(7);
    }
  }
  double? altitude;
  final a = _altitudeFeet.firstMatch(text);
  if (a != null) {
    altitude = int.parse(a.group(1)!) * _feetToMeters;
    text = text.replaceRange(a.start, a.end, '');
  }
  return _Extras(text.trim(), speedKmh: speed, courseDeg: course, altitudeM: altitude);
}

/// Counts blanked digits that are contiguous from the least significant end,
/// at the given string [positions] (least significant first). -1 when blanks
/// appear anywhere else (malformed).
int _countBlanks(String text, List<int> positions) {
  var count = 0;
  var stillBlank = true;
  for (final i in positions) {
    final blank = text[i] == ' ';
    if (blank && stillBlank) {
      count++;
    } else if (blank) {
      return -1;
    } else {
      stillBlank = false;
    }
  }
  if (text.substring(0, 2).contains(' ') && positions.length == 4 && text.length == 8) {
    // degrees must never be blank
    return -1;
  }
  return count;
}

int? _digits(String text) => int.tryParse(text.trim().isEmpty ? '' : text.replaceAll(' ', '0'));

double? _minutes(String whole, String hundredths) {
  final w = int.tryParse(whole.replaceAll(' ', '0'));
  final h = int.tryParse(hundredths.replaceAll(' ', '0'));
  if (w == null || h == null || w > 59) return null;
  return w + h / 100;
}

/// Half the width of the blanked square, in minutes, so the point is the centre.
double _centreOffsetMinutes(int ambiguity) => switch (ambiguity) {
      1 => 0.05,
      2 => 0.5,
      3 => 5,
      4 => 30,
      _ => 0,
    };

int? _base91(String four) {
  var value = 0;
  for (final u in four.codeUnits) {
    final v = u - 33;
    if (v < 0 || v > 90) return null;
    value = value * 91 + v;
  }
  return value;
}

double _pow(double base, int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}

bool _inRange(double lat, double lon) => lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
