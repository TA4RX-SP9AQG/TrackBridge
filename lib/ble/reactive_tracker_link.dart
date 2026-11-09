import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'tracker_link.dart';
import '../l10n/app_strings.dart';

/// [TrackerLink] on top of flutter_reactive_ble.
class ReactiveTrackerLink implements TrackerLink {
  /// [requireLocationServices] must be true on Android 11 and older, where BLE
  /// scan results are only delivered while the phone's location is switched on.
  ReactiveTrackerLink({FlutterReactiveBle? ble, this.requireLocationServices = false})
      : _ble = ble ?? FlutterReactiveBle();

  final bool requireLocationServices;

  static const int _requestedMtu = 247;
  static const Duration _connectTimeout = Duration(seconds: 15);
  static const int _maxBackoffSeconds = 30;

  final FlutterReactiveBle _ble;
  final _infoController = StreamController<LinkInfo>.broadcast();
  final _incomingController = StreamController<Uint8List>.broadcast();

  LinkInfo _info = const LinkInfo();
  String? _wantedId;
  int _generation = 0;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _retryTimer;
  bool _triedClearingCache = false;
  Future<void> _writeTail = Future<void>.value();

  Uuid get _service => Uuid.parse(kKissServiceUuid);

  QualifiedCharacteristic _characteristic(String deviceId, String uuid) =>
      QualifiedCharacteristic(serviceId: _service, characteristicId: Uuid.parse(uuid), deviceId: deviceId);

  @override
  LinkInfo get info => _info;

  @override
  Stream<LinkInfo> get infoStream => _infoController.stream;

  @override
  Stream<Uint8List> get incoming => _incomingController.stream;

  @override
  Stream<AdapterState> get adapterState => _ble.statusStream.map(
        (s) => switch (s) {
          BleStatus.ready => AdapterState.ready,
          BleStatus.poweredOff => AdapterState.off,
          BleStatus.unauthorized => AdapterState.unauthorized,
          BleStatus.unsupported => AdapterState.unavailable,
          _ => AdapterState.unknown,
        },
      );

  @override
  Stream<FoundTracker> scan() => _ble
      .scanForDevices(
        withServices: [_service],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: requireLocationServices,
      )
      .map((d) => FoundTracker(id: d.id, name: d.name.isEmpty ? '(isimsiz)' : d.name, rssi: d.rssi));

  void _emit(LinkInfo next) {
    _info = next;
    if (!_infoController.isClosed) _infoController.add(next);
  }

  @override
  Future<void> connect(String id, {String? name}) async {
    final request = ++_generation; // invalidates everything still in flight
    _wantedId = id;
    _triedClearingCache = false;
    _emit(LinkInfo(status: LinkStatus.connecting, deviceId: id, deviceName: name));
    await _closeConnection(bumpGeneration: false);
    if (request != _generation) return; // superseded by a newer connect() or a disconnect()
    _open(id);
  }

  void _open(String id) {
    final generation = ++_generation;
    unawaited(_connectionSub?.cancel());
    _connectionSub = _ble.connectToDevice(id: id, connectionTimeout: _connectTimeout).listen(
          (update) {
            if (generation != _generation) return;
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                unawaited(_setUp(id, generation));
              case DeviceConnectionState.disconnected:
                _onLost(id, generation, update.failure?.message);
              case DeviceConnectionState.connecting:
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (Object e) => _onLost(id, generation, e.toString()),
        );
  }

  Future<void> _setUp(String id, int generation) async {
    try {
      var mtu = 23;
      try {
        mtu = await _ble.requestMtu(deviceId: id, mtu: _requestedMtu);
      } on Object {
        // Keep the default MTU; writes are chunked to fit it.
      }
      await _ble.discoverAllServices(id);
      final services = await _ble.getDiscoveredServices(id);
      if (!services.any((s) => s.id == _service)) {
        throw StateError(t('Cihazda KISS servisi bulunamadı (bu bir LoRa tracker değil mi, ya da KISS modu kapalı?).'));
      }
      if (generation != _generation) return;
      final previous = _notifySub;
      _notifySub = null;
      await previous?.cancel();
      if (generation != _generation) return; // re-check: the await above can race with disconnect/reconnect
      _notifySub = _ble.subscribeToCharacteristic(_characteristic(id, kKissNotifyUuid)).listen(
            (data) {
              if (!_incomingController.isClosed) _incomingController.add(Uint8List.fromList(data));
            },
            onError: (Object e) => _onLost(id, generation, e.toString()),
          );
      if (generation != _generation) return;
      _emit(_info.copyWith(status: LinkStatus.connected, mtu: mtu, clearError: true, attempt: 0));
    } on Object catch (e) {
      if (generation != _generation) return;
      await _maybeClearCache(id);
      _onLost(id, generation, e.toString());
    }
  }

  /// Android keeps a GATT cache per device; a stale one can hide the service.
  Future<void> _maybeClearCache(String id) async {
    if (_triedClearingCache) return;
    _triedClearingCache = true;
    try {
      await _ble.clearGattCache(id);
    } on Object {
      // Not supported on this platform.
    }
  }

  void _onLost(String id, int generation, String? reason) {
    if (generation != _generation || _wantedId != id) return;
    unawaited(_connectionSub?.cancel());
    unawaited(_notifySub?.cancel());
    _connectionSub = null;
    _notifySub = null;
    final attempt = _info.attempt + 1;
    final delay = Duration(seconds: min(pow(2, attempt).toInt(), _maxBackoffSeconds));
    _emit(_info.copyWith(
      status: LinkStatus.connecting,
      error: reason ?? t('Bağlantı koptu.'),
      attempt: attempt,
    ));
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (_wantedId == id) _open(id);
    });
  }

  Future<void> _closeConnection({bool bumpGeneration = true}) async {
    if (bumpGeneration) _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    final conn = _connectionSub;
    final notify = _notifySub;
    _connectionSub = null;
    _notifySub = null;
    await notify?.cancel();
    await conn?.cancel(); // cancelling the connect stream disconnects the device
  }

  @override
  Future<void> disconnect() async {
    _wantedId = null;
    await _closeConnection();
    _emit(const LinkInfo());
  }

  /// Writes are queued so the chunks of two frames can never interleave on the
  /// air interface of the tracker (an interleaved frame would be transmitted
  /// as garbage).
  @override
  Future<void> write(Uint8List bytes) {
    final run = _writeTail.then((_) => _writeNow(bytes));
    _writeTail = run.catchError((Object _) {});
    return run;
  }

  Future<void> _writeNow(Uint8List bytes) async {
    final generation = _generation;
    final id = _info.deviceId;
    if (!_info.isConnected || id == null) throw StateError(t('Tracker bağlı değil.'));
    final chunkSize = max(20, _info.mtu - 3);
    final characteristic = _characteristic(id, kKissWriteUuid);
    for (var i = 0; i < bytes.length; i += chunkSize) {
      if (generation != _generation || !_info.isConnected) {
        throw StateError(t('Bağlantı koptu, paket gönderilemedi.'));
      }
      final end = min(i + chunkSize, bytes.length);
      await _ble.writeCharacteristicWithResponse(characteristic, value: bytes.sublist(i, end));
    }
  }

  @override
  Future<void> dispose() async {
    _wantedId = null;
    await _closeConnection();
    await _infoController.close();
    await _incomingController.close();
  }
}
