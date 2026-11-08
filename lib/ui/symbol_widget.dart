import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/symbols.dart';

/// Edge length of one tile in the bundled sprite sheets.
const double kSymbolTilePx = 128;

const String _assetDir = 'assets/symbols/hessu';

/// The three sprite sheets (primary, alternate, overlay glyphs).
class SymbolSheets {
  SymbolSheets._(this.primary, this.alternate, this.overlay);

  final ui.Image primary;
  final ui.Image alternate;
  final ui.Image overlay;

  static SymbolSheets? _loaded;
  static Future<SymbolSheets>? _loading;

  /// The sheets if they are already decoded, otherwise null.
  static SymbolSheets? get loadedOrNull => _loaded;

  /// Decodes the sheets once; later calls return the same instance.
  static Future<SymbolSheets> load({AssetBundle? bundle}) =>
      _loading ??= _decodeAll(bundle ?? rootBundle).then((s) => _loaded = s);

  static Future<SymbolSheets> _decodeAll(AssetBundle bundle) async {
    final images = await Future.wait([
      _decode(bundle, '$_assetDir/aprs-symbols-128-0.png'),
      _decode(bundle, '$_assetDir/aprs-symbols-128-1.png'),
      _decode(bundle, '$_assetDir/aprs-symbols-128-2.png'),
    ]);
    return SymbolSheets._(images[0], images[1], images[2]);
  }

  static Future<ui.Image> _decode(AssetBundle bundle, String path) async {
    final data = await bundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }
}

/// Draws an APRS symbol from the sprite sheets. [table] is the APRS table
/// character: `/`, `\` or an overlay character (0-9, A-Z). Invalid pairs are
/// drawn as a neutral marker with the two characters, never as an error.
class AprsSymbolIcon extends StatelessWidget {
  const AprsSymbolIcon({super.key, required this.table, required this.code, this.size = 32});

  final String table;
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ready = SymbolSheets.loadedOrNull;
    if (ready != null) return _paint(ready);
    return FutureBuilder<SymbolSheets>(
      future: SymbolSheets.load(),
      builder: (context, snapshot) {
        final sheets = snapshot.data;
        return sheets == null ? SizedBox.square(dimension: size) : _paint(sheets);
      },
    );
  }

  Widget _paint(SymbolSheets sheets) => SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _SymbolPainter(sheets, resolveSymbol(table, code), '$table$code'),
        ),
      );
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.sheets, this.resolved, this.label);

  final SymbolSheets sheets;
  final ResolvedSymbol? resolved;
  final String label;

  static const Rect _unit = Rect.fromLTWH(0, 0, kSymbolTilePx, kSymbolTilePx);

  Rect? _source(String code) {
    final cell = spriteCell(code);
    if (cell == null) return null;
    return _unit.shift(Offset(cell.col * kSymbolTilePx, cell.row * kSymbolTilePx));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final target = Offset.zero & size;
    final symbol = resolved;
    final src = symbol == null ? null : _source(symbol.info.code);
    if (symbol == null || src == null) {
      _paintFallback(canvas, size);
      return;
    }
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final sheet = symbol.info.table == '/' ? sheets.primary : sheets.alternate;
    canvas.drawImageRect(sheet, src, target, paint);
    final overlay = symbol.overlay;
    final overlaySrc = overlay == null ? null : _source(overlay);
    if (overlaySrc != null) canvas.drawImageRect(sheets.overlay, overlaySrc, target, paint);
  }

  void _paintFallback(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    canvas.drawCircle(size.center(Offset.zero), r * 0.9, Paint()..color = const Color(0xFF8A94A6));
    final text = TextPainter(
      text: TextSpan(
        text: label.trim().isEmpty ? '?' : label,
        style: TextStyle(color: Colors.white, fontSize: size.shortestSide * 0.32, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width);
    text.paint(canvas, size.center(Offset.zero) - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      old.sheets != sheets || old.label != label || old.resolved?.info.code != resolved?.info.code;
}
