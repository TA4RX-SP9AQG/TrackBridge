import 'dart:typed_data';

/// GATT layout of the tracker's KISS-over-BLE service (firmware `ble_utils.cpp`).
const String kKissServiceUuid = '00000001-ba2a-46c9-ae49-01b0961f68bb';

/// Tracker -> phone (read + notify).
const String kKissNotifyUuid = '00000003-ba2a-46c9-ae49-01b0961f68bb';

/// Phone -> tracker (write, write without response).
const String kKissWriteUuid = '00000002-ba2a-46c9-ae49-01b0961f68bb';

enum LinkStatus { disconnected, connecting, connected }

enum AdapterState { ready, off, unauthorized, unavailable, unknown }

/// Immutable snapshot of the connection.
class LinkInfo {
  const LinkInfo({
    this.status = LinkStatus.disconnected,
    this.deviceId,
    this.deviceName,
    this.mtu = 23,
    this.error,
    this.attempt = 0,
  });

  final LinkStatus status;
  final String? deviceId;
  final String? deviceName;

  /// Negotiated ATT MTU (23 is the BLE default).
  final int mtu;

  /// Last error, shown to the user. Null when everything is fine.
  final String? error;

  /// Reconnect attempt counter (0 for the first try).
  final int attempt;

  bool get isConnected => status == LinkStatus.connected;

  LinkInfo copyWith({
    LinkStatus? status,
    String? deviceId,
    String? deviceName,
    int? mtu,
    String? error,
    bool clearError = false,
    int? attempt,
  }) =>
      LinkInfo(
        status: status ?? this.status,
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        mtu: mtu ?? this.mtu,
        error: clearError ? null : (error ?? this.error),
        attempt: attempt ?? this.attempt,
      );
}

/// A tracker seen while scanning.
class FoundTracker {
  const FoundTracker({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;
}

/// What the rest of the app needs from the Bluetooth link. A fake
/// implementation is used in tests.
abstract class TrackerLink {
  LinkInfo get info;
  Stream<LinkInfo> get infoStream;

  /// Raw notification payloads from the tracker (parts of KISS frames).
  Stream<Uint8List> get incoming;

  Stream<AdapterState> get adapterState;

  /// Scans for trackers advertising the KISS service until the listener cancels.
  Stream<FoundTracker> scan();

  /// Connects and keeps reconnecting until [disconnect] is called.
  Future<void> connect(String id, {String? name});

  Future<void> disconnect();

  /// Writes [bytes] to the tracker, split to fit the MTU. Throws [StateError]
  /// when not connected.
  Future<void> write(Uint8List bytes);

  Future<void> dispose();
}
