import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackbridge/core/tile_url.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/state/settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults when nothing is stored', () async {
    final s = await PrefsSettingsStore().load();
    expect(s.callsign, '');
    expect(s.tileUrl, kDefaultTileUrl);
    expect(s.ambiguity, 2);
    expect(s.positionSource, PositionSource.manual);
  });

  test('everything round-trips, including the tile URL and optional values', () async {
    final store = PrefsSettingsStore();
    const saved = AppSettings(
      callsign: 'SP9AQG-9',
      path: 'WIDE1-1',
      symbolTable: 'S',
      symbol: '#',
      comment: 'hello',
      ambiguity: 3,
      positionSource: PositionSource.phone,
      manualLat: 52.2297,
      manualLon: 21.0122,
      autoAck: false,
      noticeAccepted: true,
      lastDeviceId: 'AA:BB',
      lastDeviceName: 'LoRaTracker',
      tileUrl: 'https://tiles.example.com/{z}/{x}/{y}.png',
    );
    await store.save(saved);
    final loaded = await store.load();
    expect(loaded.callsign, 'SP9AQG-9');
    expect((loaded.symbolTable, loaded.symbol), ('S', '#'));
    expect(loaded.ambiguity, 3);
    expect(loaded.positionSource, PositionSource.phone);
    expect((loaded.manualLat, loaded.manualLon), (52.2297, 21.0122));
    expect(loaded.autoAck, isFalse);
    expect(loaded.lastDeviceName, 'LoRaTracker');
    expect(loaded.tileUrl, 'https://tiles.example.com/{z}/{x}/{y}.png');
  });

  test('an invalid stored tile URL falls back to the default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'tb.tileUrl': 'http://evil.example/x.png'});
    expect((await PrefsSettingsStore().load()).tileUrl, kDefaultTileUrl);
  });

  test('clearing an optional value removes it', () async {
    final store = PrefsSettingsStore();
    await store.save(const AppSettings(manualLat: 1, manualLon: 2, lastDeviceId: 'x'));
    await store.save(const AppSettings());
    final loaded = await store.load();
    expect((loaded.manualLat, loaded.manualLon, loaded.lastDeviceId), (null, null, null));
  });

  test('ambiguity is clamped to 0-4', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'tb.ambiguity': 99});
    expect((await PrefsSettingsStore().load()).ambiguity, 4);
  });
}
