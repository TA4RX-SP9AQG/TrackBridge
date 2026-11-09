import 'package:shared_preferences/shared_preferences.dart';

import '../core/tile_url.dart';

import 'models.dart';

/// Persists [AppSettings]. The interface lets tests use an in-memory store.
abstract class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

class PrefsSettingsStore implements SettingsStore {
  static const _prefix = 'tb.';

  @override
  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    const defaults = AppSettings();
    final sourceName = p.getString('${_prefix}positionSource');
    return AppSettings(
      callsign: p.getString('${_prefix}callsign') ?? defaults.callsign,
      path: p.getString('${_prefix}path') ?? defaults.path,
      symbolTable: p.getString('${_prefix}symbolTable') ?? defaults.symbolTable,
      symbol: p.getString('${_prefix}symbol') ?? defaults.symbol,
      comment: p.getString('${_prefix}comment') ?? defaults.comment,
      ambiguity: (p.getInt('${_prefix}ambiguity') ?? defaults.ambiguity).clamp(0, 4),
      positionSource: PositionSource.values.firstWhere(
        (s) => s.name == sourceName,
        orElse: () => defaults.positionSource,
      ),
      manualLat: p.getDouble('${_prefix}manualLat'),
      manualLon: p.getDouble('${_prefix}manualLon'),
      autoAck: p.getBool('${_prefix}autoAck') ?? defaults.autoAck,
      carVoiceReply: p.getBool('${_prefix}carVoiceReply') ?? defaults.carVoiceReply,
      wavelogUrl: p.getString('${_prefix}wavelogUrl') ?? defaults.wavelogUrl,
      wavelogKey: p.getString('${_prefix}wavelogKey') ?? defaults.wavelogKey,
      wavelogProfileId: p.getString('${_prefix}wavelogProfileId') ?? defaults.wavelogProfileId,
      wavelogFreqMhz: p.getDouble('${_prefix}wavelogFreqMhz') ?? defaults.wavelogFreqMhz,
      noticeAccepted: p.getBool('${_prefix}noticeAccepted') ?? defaults.noticeAccepted,
      lastDeviceId: p.getString('${_prefix}lastDeviceId'),
      lastDeviceName: p.getString('${_prefix}lastDeviceName'),
      tileUrl: _validTileUrl(p.getString('${_prefix}tileUrl')),
    );
  }

  @override
  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setString('${_prefix}callsign', s.callsign),
      p.setString('${_prefix}path', s.path),
      p.setString('${_prefix}symbolTable', s.symbolTable),
      p.setString('${_prefix}symbol', s.symbol),
      p.setString('${_prefix}comment', s.comment),
      p.setInt('${_prefix}ambiguity', s.ambiguity),
      p.setString('${_prefix}positionSource', s.positionSource.name),
      _setOrRemoveDouble(p, '${_prefix}manualLat', s.manualLat),
      _setOrRemoveDouble(p, '${_prefix}manualLon', s.manualLon),
      p.setBool('${_prefix}autoAck', s.autoAck),
      p.setBool('${_prefix}carVoiceReply', s.carVoiceReply),
      p.setString('${_prefix}wavelogUrl', s.wavelogUrl),
      p.setString('${_prefix}wavelogKey', s.wavelogKey),
      p.setString('${_prefix}wavelogProfileId', s.wavelogProfileId),
      p.setDouble('${_prefix}wavelogFreqMhz', s.wavelogFreqMhz),
      p.setBool('${_prefix}noticeAccepted', s.noticeAccepted),
      _setOrRemoveString(p, '${_prefix}lastDeviceId', s.lastDeviceId),
      _setOrRemoveString(p, '${_prefix}lastDeviceName', s.lastDeviceName),
      p.setString('${_prefix}tileUrl', s.tileUrl),
    ]);
  }

  String _validTileUrl(String? stored) => stored != null && isValidTileUrl(stored) ? stored : kDefaultTileUrl;

  Future<bool> _setOrRemoveDouble(SharedPreferences p, String key, double? v) =>
      v == null ? p.remove(key) : p.setDouble(key, v);

  Future<bool> _setOrRemoveString(SharedPreferences p, String key, String? v) =>
      v == null ? p.remove(key) : p.setString(key, v);
}
