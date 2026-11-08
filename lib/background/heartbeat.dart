import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the heartbeat has recorded so far.
class HeartbeatSnapshot {
  const HeartbeatSnapshot({this.count = 0, this.startedAt, this.lastTick, this.maxGapSeconds = 0});

  final int count;
  final DateTime? startedAt;
  final DateTime? lastTick;

  /// Longest time between two ticks. Much more than the interval means the process was frozen or starved.
  final int maxGapSeconds;
}

/// Persists the last snapshot so the run before a process death can be inspected afterwards.
abstract class HeartbeatStore {
  Future<HeartbeatSnapshot?> load();
  Future<void> save(HeartbeatSnapshot snapshot);
}

class PrefsHeartbeatStore implements HeartbeatStore {
  static const _count = 'tb.hb.count';
  static const _started = 'tb.hb.started';
  static const _last = 'tb.hb.last';
  static const _gap = 'tb.hb.gap';

  @override
  Future<HeartbeatSnapshot?> load() async {
    final p = await SharedPreferences.getInstance();
    final count = p.getInt(_count);
    if (count == null) return null;
    return HeartbeatSnapshot(
      count: count,
      startedAt: DateTime.tryParse(p.getString(_started) ?? ''),
      lastTick: DateTime.tryParse(p.getString(_last) ?? ''),
      maxGapSeconds: p.getInt(_gap) ?? 0,
    );
  }

  @override
  Future<void> save(HeartbeatSnapshot s) async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt(_count, s.count),
      if (s.startedAt != null) p.setString(_started, s.startedAt!.toIso8601String()),
      if (s.lastTick != null) p.setString(_last, s.lastTick!.toIso8601String()),
      p.setInt(_gap, s.maxGapSeconds),
    ]);
  }
}

/// A timer that proves the Dart side keeps running while the app is in the
/// background or the screen is off. It exists to test the background setup on
/// a real phone and is cheap enough to leave running.
class Heartbeat extends ChangeNotifier {
  Heartbeat({required this._store, DateTime Function()? now, this.interval = const Duration(seconds: 10)})
      : _now = now ?? DateTime.now;

  final HeartbeatStore _store;
  final DateTime Function() _now;
  final Duration interval;

  Timer? _timer;
  HeartbeatSnapshot _snapshot = const HeartbeatSnapshot();
  HeartbeatSnapshot? _previousRun;

  HeartbeatSnapshot get snapshot => _snapshot;

  /// The run saved by an earlier process, if any (not counted in [snapshot]).
  HeartbeatSnapshot? get previousRun => _previousRun;
  bool get running => _timer != null;

  Duration get uptime {
    final started = _snapshot.startedAt;
    return started == null ? Duration.zero : _now().difference(started);
  }

  Future<void> start() async {
    if (_timer != null) return;
    _previousRun = await _store.load();
    _snapshot = HeartbeatSnapshot(startedAt: _now());
    _timer = Timer.periodic(interval, (_) => tick());
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  /// Records one beat. Public so tests can drive it without waiting.
  @visibleForTesting
  void tick() {
    final now = _now();
    final last = _snapshot.lastTick ?? _snapshot.startedAt;
    final gap = last == null ? 0 : now.difference(last).inSeconds;
    _snapshot = HeartbeatSnapshot(
      count: _snapshot.count + 1,
      startedAt: _snapshot.startedAt,
      lastTick: now,
      maxGapSeconds: gap > _snapshot.maxGapSeconds ? gap : _snapshot.maxGapSeconds,
    );
    unawaited(_store.save(_snapshot));
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
