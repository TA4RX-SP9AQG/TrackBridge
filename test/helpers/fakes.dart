import 'dart:async';
import 'dart:typed_data';

import 'package:trackbridge/ble/tracker_link.dart';
import 'package:trackbridge/core/ax25.dart';
import 'package:trackbridge/core/kiss_codec.dart';
import 'package:trackbridge/state/models.dart';
import 'package:trackbridge/state/settings_store.dart';

// Shared test doubles: a fake tracker link, an in-memory settings store and frame helpers.

class FakeLink implements TrackerLink {
  final _info = StreamController<LinkInfo>.broadcast();
  final _incoming = StreamController<Uint8List>.broadcast();
  final List<Uint8List> written = [];
  LinkInfo current = const LinkInfo();
  Object? writeError;

  void setConnected(bool connected) {
    current = LinkInfo(
      status: connected ? LinkStatus.connected : LinkStatus.disconnected,
      deviceId: 'AA:BB',
      deviceName: 'LoRaTracker',
      mtu: 247,
    );
    _info.add(current);
  }

  void receive(Uint8List bytes) => _incoming.add(bytes);

  @override
  LinkInfo get info => current;
  @override
  Stream<LinkInfo> get infoStream => _info.stream;
  @override
  Stream<Uint8List> get incoming => _incoming.stream;
  @override
  Stream<AdapterState> get adapterState => const Stream<AdapterState>.empty();
  @override
  Stream<FoundTracker> scan() => const Stream<FoundTracker>.empty();
  @override
  Future<void> connect(String id, {String? name}) async => setConnected(true);
  @override
  Future<void> disconnect() async => setConnected(false);
  @override
  Future<void> write(Uint8List bytes) async {
    if (!current.isConnected) throw StateError('Tracker bağlı değil.');
    if (writeError != null) throw writeError!;
    written.add(bytes);
  }

  @override
  Future<void> dispose() async {}
}

class MemoryStore implements SettingsStore {
  MemoryStore(this.value);
  AppSettings value;
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async => value = settings;
}

Uint8List frameBytes(String src, String dst, String info, {List<String> path = const []}) => kissEncode(
      Ax25Frame(
        destination: Ax25Address.parse(dst),
        source: Ax25Address.parse(src),
        digipeaters: path.map(Ax25Address.parse).toList(),
        info: Uint8List.fromList(info.codeUnits),
      ).encode(),
    );

String decodeWritten(Uint8List kiss) {
  final frame = KissDeframer().add(kiss).single;
  return Ax25Frame.decode(frame.data)!.toTnc2();
}

Future<void> pump() => Future<void>.delayed(Duration.zero);
