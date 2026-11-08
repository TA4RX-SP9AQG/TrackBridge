import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:trackbridge/core/navigation_links.dart';
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

/// Records the URIs that would be opened; `accepts` lists the schemes that "work".
class FakeLauncher implements UriLauncher {
  FakeLauncher({this.accepts = const {}, this.throwFor = const {}});

  final Set<String> accepts;
  final Set<String> throwFor;
  final List<Uri> tried = [];

  @override
  Future<bool> launch(Uri uri) async {
    tried.add(uri);
    if (throwFor.contains(uri.scheme)) throw StateError('no activity');
    return accepts.contains(uri.scheme);
  }
}

// A 1x1 transparent PNG, so map tests never touch the network.
final Uint8List _transparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x60, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0xA5, 0xF6, 0x45, 0x40, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class EmptyTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_transparentPng);
}
