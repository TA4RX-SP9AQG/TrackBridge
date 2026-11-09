import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/smart_beacon.dart';
import 'app_controller.dart';
import 'models.dart';
import 'phone_position.dart';

/// One GPS reading from the phone.
class PhoneFix {
  const PhoneFix({
    required this.lat,
    required this.lon,
    required this.speedKmh,
    required this.accuracyM,
    required this.time,
    this.headingDeg,
  });

  final double lat;
  final double lon;
  final double speedKmh;
  final double? headingDeg;
  final double accuracyM;
  final DateTime time;
}

enum StartResult { started, notConnected, noPosition, badConfig, needsPhoneGps }

enum AutoBeaconMode { interval, smart }

class AutoBeaconConfig {
  const AutoBeaconConfig._(this.mode, this.interval, this.params);

  factory AutoBeaconConfig.interval(Duration interval) => AutoBeaconConfig._(AutoBeaconMode.interval, interval, null);

  factory AutoBeaconConfig.smart(SmartBeaconParams params) => AutoBeaconConfig._(AutoBeaconMode.smart, null, params);

  final AutoBeaconMode mode;
  final Duration? interval;
  final SmartBeaconParams? params;
}

class AutoBeaconLogEntry {
  const AutoBeaconLogEntry({required this.time, required this.text, required this.reason});

  final DateTime time;
  final String text;
  final String reason;
}

/// Sends position beacons on its own, on a fixed interval or when the phone moves (SmartBeaconing).
///
/// This is unattended radio transmission, so it is deliberately strict:
/// - it is **off** whenever the app starts and is never saved as "on";
/// - it needs a connected tracker and **stops** the moment the connection drops (it does not resume on
///   reconnect);
/// - phone GPS fixes must be fresh and accurate, otherwise the beacon is skipped and the reason shown;
/// - at least [minGap] between two automatic beacons, whatever the algorithm says;
/// - every automatic beacon is logged.
class AutoBeaconController extends ChangeNotifier {
  AutoBeaconController({required this.app, DateTime Function()? now}) : _now = now ?? DateTime.now {
    app.addListener(_onAppChanged);
  }

  static const Duration minGap = Duration(seconds: 60);
  static const Duration minInterval = Duration(minutes: 1);
  static const Duration maxFixAge = Duration(seconds: 30);
  static const double maxAccuracyM = 100;
  static const int maxLog = 20;

  final AppController app;
  final DateTime Function() _now;

  AutoBeaconConfig? _config;
  SmartBeaconEngine? _engine;
  PhoneFix? _fix;
  DateTime? _lastSent;
  String _status = 'Kapalı';
  final List<AutoBeaconLogEntry> _log = [];
  bool _busy = false;
  bool _disposed = false;

  bool get running => _config != null;
  String get status => _status;
  DateTime? get lastSent => _lastSent;
  PhoneFix? get lastFix => _fix;

  /// Newest first, at most [maxLog].
  List<AutoBeaconLogEntry> get log => List.unmodifiable(_log);

  bool get _usesPhone => app.settings.positionSource == PositionSource.phone;

  /// Feed GPS readings from the phone here (a no-op for the fixed position source).
  void onFix(PhoneFix fix) {
    _fix = fix;
    if (!_disposed) notifyListeners();
  }

  Future<StartResult> start(AutoBeaconConfig config) async {
    if (!app.linkInfo.isConnected) return StartResult.notConnected;
    if (config.mode == AutoBeaconMode.interval) {
      final interval = config.interval!;
      if (interval < minInterval) return StartResult.badConfig;
    } else {
      if (!_usesPhone) return StartResult.needsPhoneGps;
      try {
        config.params!.validate();
      } on ArgumentError {
        return StartResult.badConfig;
      }
    }
    if (_resolvePosition() == null) return StartResult.noPosition;
    _config = config;
    _engine = config.mode == AutoBeaconMode.smart ? SmartBeaconEngine(config.params!) : null;
    _lastSent = null;
    _status = 'Başlatılıyor...';
    notifyListeners();
    await _send('ilk beacon');
    return StartResult.started;
  }

  void stop([String reason = 'Kapalı']) {
    _config = null;
    _engine = null;
    _status = reason;
    if (!_disposed) notifyListeners();
  }

  /// Called every few seconds by a timer (and by tests).
  Future<void> tick() async {
    final config = _config;
    if (config == null || _busy) return;
    final now = _now();
    final last = _lastSent;
    if (last != null && now.difference(last) < minGap) return;
    if (config.mode == AutoBeaconMode.interval) {
      if (last == null || now.difference(last) >= config.interval!) await _send('aralık');
      return;
    }
    final fix = _fix;
    if (fix == null) {
      _setStatus('GPS konumu bekleniyor');
      return;
    }
    final problem = _fixProblem(fix);
    if (problem != null) {
      _setStatus(problem);
      return;
    }
    final decision = _engine!.evaluate(SmartFix(speedKmh: fix.speedKmh, headingDeg: fix.headingDeg, time: now));
    if (decision == BeaconDecision.none) {
      _setStatus('Hareket izleniyor');
      return;
    }
    await _send(decision == BeaconDecision.turn ? 'dönüş' : 'hız');
  }

  // ---- internals ----

  String? _fixProblem(PhoneFix fix) {
    if (_now().difference(fix.time) > maxFixAge) return 'GPS konumu eski, güncel konum bekleniyor';
    if (fix.accuracyM > maxAccuracyM) return 'GPS yeterince hassas değil (${fix.accuracyM.round()} m)';
    return null;
  }

  GeoPoint? _resolvePosition() {
    if (_usesPhone) {
      final fix = _fix;
      if (fix == null || _fixProblem(fix) != null) return null;
      return GeoPoint(fix.lat, fix.lon);
    }
    final s = app.settings;
    final lat = s.manualLat;
    final lon = s.manualLon;
    return lat == null || lon == null ? null : GeoPoint(lat, lon);
  }

  Future<void> _send(String reason) async {
    if (_busy) return;
    final point = _resolvePosition();
    if (point == null) {
      _setStatus(_usesPhone ? (_fix == null ? 'GPS konumu bekleniyor' : (_fixProblem(_fix!) ?? 'Konum yok')) : 'Konum ayarlı değil');
      return;
    }
    _busy = true;
    try {
      final packet = await app.buildBeaconPacket(position: point);
      await app.transmit(packet);
      final now = _now();
      _lastSent = now;
      _engine?.markSent(SmartFix(speedKmh: _fix?.speedKmh ?? 0, headingDeg: _fix?.headingDeg, time: now));
      _log.insert(0, AutoBeaconLogEntry(time: now, text: packet.tnc2, reason: reason));
      if (_log.length > maxLog) _log.removeRange(maxLog, _log.length);
      _setStatus('Son beacon gönderildi ($reason)');
    } on Object catch (e) {
      _setStatus('Beacon gönderilemedi: $e');
    } finally {
      _busy = false;
    }
  }

  void _setStatus(String text) {
    if (_status == text) return;
    _status = text;
    if (!_disposed) notifyListeners();
  }

  void _onAppChanged() {
    if (_config != null && !app.linkInfo.isConnected) stop('Tracker bağlantısı koptu, otomatik beacon durdu');
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_onAppChanged);
    super.dispose();
  }
}
