import '../core/aprs_position.dart';

/// A station, object or item whose position was heard on the radio.
class Station {
  const Station({
    required this.id,
    required this.displayName,
    required this.owner,
    required this.position,
    required this.lastHeard,
    required this.path,
    required this.viaDigipeater,
    this.packetCount = 1,
  });

  /// Station id for a position packet. Objects and items are keyed by their
  /// own name; stations by the sender's callsign.
  factory Station.fromPacket({
    required String sender,
    required AprsPosition position,
    required DateTime heardAt,
    required String path,
    required bool viaDigipeater,
  }) {
    final name = position.objectName;
    return Station(
      id: name == null ? 'stn/$sender' : 'obj/$name',
      displayName: name ?? sender,
      owner: sender,
      position: position,
      lastHeard: heardAt,
      path: path,
      viaDigipeater: viaDigipeater,
    );
  }

  final String id;
  final String displayName;

  /// The callsign that sent the packet (for objects: who published it).
  final String owner;
  final AprsPosition position;
  final DateTime lastHeard;

  /// Digipeater path as received, for example `SP9KKK-2*`.
  final String path;

  /// True when a digipeater had repeated the packet (not heard directly).
  final bool viaDigipeater;
  final int packetCount;

  bool get isObject => position.objectName != null;
}

/// Immutable collection of heard stations. Every change returns a new table.
class StationTable {
  const StationTable([this._byId = const <String, Station>{}]);

  static const int maxStations = 500;
  static const Duration maxAge = Duration(hours: 24);

  final Map<String, Station> _byId;

  /// Newest first.
  List<Station> get all => (_byId.values.toList()..sort((a, b) => b.lastHeard.compareTo(a.lastHeard)));

  Station? operator [](String id) => _byId[id];

  /// Adds or replaces [incoming], removes killed objects, drops entries older
  /// than [maxAge] (relative to [now]) and keeps at most [maxStations].
  StationTable update(Station incoming, DateTime now) {
    final next = Map<String, Station>.of(_byId);
    if (incoming.position.killed) {
      next.remove(incoming.id);
    } else {
      final previous = next[incoming.id];
      next[incoming.id] = previous == null
          ? incoming
          : Station(
              id: incoming.id,
              displayName: incoming.displayName,
              owner: incoming.owner,
              position: incoming.position,
              lastHeard: incoming.lastHeard,
              path: incoming.path,
              viaDigipeater: incoming.viaDigipeater,
              packetCount: previous.packetCount + 1,
            );
    }
    next.removeWhere((_, s) => now.difference(s.lastHeard) > maxAge);
    if (next.length > maxStations) {
      final newest = next.values.toList()..sort((a, b) => b.lastHeard.compareTo(a.lastHeard));
      return StationTable({for (final s in newest.take(maxStations)) s.id: s});
    }
    return StationTable(next);
  }
}
