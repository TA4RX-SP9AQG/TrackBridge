import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the real Roboto and Material Icons fonts from the Flutter SDK so layout tests measure text
/// like a phone does (the default test font, Ahem, is far wider and gives false overflow alarms).
///
/// Returns false when the SDK fonts cannot be found; callers should then skip width-sensitive tests.
Future<bool> loadRealFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  final regular = File('$dir/roboto-regular.ttf');
  final icons = File('$dir/materialicons-regular.otf');
  if (!regular.existsSync() || !icons.existsSync()) return false;

  Future<ByteData> bytes(File f) async => ByteData.sublistView(await f.readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final name in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-italic.ttf']) {
    final f = File('$dir/$name');
    if (f.existsSync()) roboto.addFont(bytes(f));
  }
  await roboto.load();
  final mono = FontLoader('monospace')..addFont(bytes(regular));
  await mono.load();
  final materialIcons = FontLoader('MaterialIcons')..addFont(bytes(icons));
  await materialIcons.load();
  return true;
}
