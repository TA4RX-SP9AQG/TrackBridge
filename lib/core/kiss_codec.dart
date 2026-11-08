import 'dart:typed_data';

/// KISS special bytes (see the KISS TNC protocol).
const int kFend = 0xC0;
const int kFesc = 0xDB;
const int kTfend = 0xDC;
const int kTfesc = 0xDD;

/// One decoded KISS frame. [command] is the low nibble of the type byte
/// (0 = data frame), [port] the high nibble.
class KissFrame {
  const KissFrame({required this.command, required this.port, required this.data});

  final int command;
  final int port;
  final Uint8List data;

  bool get isData => command == 0;
}

/// Wraps [data] in a KISS data frame: FEND, type byte, escaped data, FEND.
Uint8List kissEncode(Uint8List data, {int command = 0}) {
  final out = <int>[kFend, command & 0x0F];
  for (final b in data) {
    if (b == kFend) {
      out
        ..add(kFesc)
        ..add(kTfend);
    } else if (b == kFesc) {
      out
        ..add(kFesc)
        ..add(kTfesc);
    } else {
      out.add(b);
    }
  }
  out.add(kFend);
  return Uint8List.fromList(out);
}

/// Reassembles KISS frames from an arbitrary stream of BLE notifications.
///
/// A frame can arrive split across several notifications, and several frames
/// can arrive in one. The deframer keeps the partial frame between calls.
class KissDeframer {
  /// Frames larger than this are dropped (the tracker firmware uses 1024 too).
  static const int maxBuffer = 1024;

  final List<int> _buf = <int>[];
  bool _inFrame = false;
  bool _escaped = false;

  int get bufferedBytes => _buf.length;

  /// Feeds [bytes] and returns every frame that became complete.
  List<KissFrame> add(List<int> bytes) {
    final frames = <KissFrame>[];
    for (final b in bytes) {
      if (b == kFend) {
        if (_inFrame && _buf.isNotEmpty) {
          frames.add(_toFrame());
        }
        _reset(inFrame: true);
        continue;
      }
      if (!_inFrame) continue; // garbage before the first FEND
      int value = b;
      if (_escaped) {
        _escaped = false;
        if (b == kTfend) {
          value = kFend;
        } else if (b == kTfesc) {
          value = kFesc;
        }
      } else if (b == kFesc) {
        _escaped = true;
        continue;
      }
      _buf.add(value);
      if (_buf.length > maxBuffer) _reset(inFrame: false); // overflow: resync on next FEND
    }
    return frames;
  }

  KissFrame _toFrame() {
    final type = _buf.first;
    return KissFrame(
      command: type & 0x0F,
      port: type >> 4,
      data: Uint8List.fromList(_buf.sublist(1)),
    );
  }

  void _reset({required bool inFrame}) {
    _buf.clear();
    _escaped = false;
    _inFrame = inFrame;
  }
}
