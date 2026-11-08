import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/tile_url.dart';

void main() {
  test('default is the OpenStreetMap standard tile URL', () {
    expect(kDefaultTileUrl, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(isValidTileUrl(kDefaultTileUrl), isTrue);
  });

  test('accepts https templates with z, x and y', () {
    expect(isValidTileUrl('https://tiles.example.com/{z}/{x}/{y}.png?key=abc'), isTrue);
    expect(isValidTileUrl('https://{s}.tile.example.org/{z}/{x}/{y}@2x.png'), isTrue);
  });

  test('rejects http, missing placeholders and junk', () {
    expect(isValidTileUrl('http://tiles.example.com/{z}/{x}/{y}.png'), isFalse);
    expect(isValidTileUrl('https://tiles.example.com/{z}/{x}.png'), isFalse);
    expect(isValidTileUrl('https://tiles.example.com/tile.png'), isFalse);
    expect(isValidTileUrl(''), isFalse);
    expect(isValidTileUrl('ftp://x/{z}/{x}/{y}'), isFalse);
    expect(isValidTileUrl('not a url {z}{x}{y}'), isFalse);
  });

  test('host label for attribution', () {
    expect(tileHost('https://tile.openstreetmap.org/{z}/{x}/{y}.png'), 'tile.openstreetmap.org');
    expect(tileHost('https://{s}.tile.example.org/{z}/{x}/{y}.png'), '{s}.tile.example.org');
    expect(isOpenStreetMapUrl(kDefaultTileUrl), isTrue);
    expect(isOpenStreetMapUrl('https://tiles.example.com/{z}/{x}/{y}.png'), isFalse);
  });
}
