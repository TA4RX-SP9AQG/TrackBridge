import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/aprs_position.dart';
import 'package:trackbridge/state/station_table.dart';

AprsPosition pos({double lat = 52.0, double lon = 21.0, String? name, bool killed = false, String comment = ''}) =>
    AprsPosition(
      lat: lat,
      lon: lon,
      symbolTable: '/',
      symbolCode: '-',
      format: PositionFormat.uncompressed,
      comment: comment,
      objectName: name,
      killed: killed,
    );

Station station(String call, DateTime t, {AprsPosition? position, bool via = false}) =>
    Station.fromPacket(sender: call, position: position ?? pos(), heardAt: t, path: via ? 'SP9KKK-2*' : '', viaDigipeater: via);

void main() {
  final t0 = DateTime(2026, 11, 8, 12);

  test('starts empty', () {
    expect(const StationTable().all, isEmpty);
  });

  test('adds a station and a newer packet replaces the position', () {
    final table = const StationTable()
        .update(station('N1TEST-7', t0, position: pos(lat: 50)), t0)
        .update(station('N1TEST-7', t0.add(const Duration(minutes: 1)), position: pos(lat: 51)), t0.add(const Duration(minutes: 1)));
    expect(table.all, hasLength(1));
    expect(table.all.single.position.lat, 51);
    expect(table.all.single.packetCount, 2);
  });

  test('update never mutates the previous table', () {
    const empty = StationTable();
    final next = empty.update(station('N1TEST-7', t0), t0);
    expect(empty.all, isEmpty);
    expect(next.all, hasLength(1));
  });

  test('objects are keyed by name, not by the sender', () {
    final table = const StationTable()
        .update(station('N1TEST-7', t0, position: pos(name: 'LEADER')), t0)
        .update(station('N1TEST-7', t0, position: pos(name: 'ROVER')), t0)
        .update(station('N1TEST-7', t0), t0);
    expect(table.all.map((s) => s.displayName).toSet(), {'LEADER', 'ROVER', 'N1TEST-7'});
    expect(table.all.firstWhere((s) => s.displayName == 'LEADER').owner, 'N1TEST-7');
  });

  test('a killed object removes the entry', () {
    var table = const StationTable().update(station('N1TEST-7', t0, position: pos(name: 'LEADER')), t0);
    table = table.update(station('N1TEST-7', t0, position: pos(name: 'LEADER', killed: true)), t0);
    expect(table.all, isEmpty);
  });

  test('entries older than 24 h are dropped on update', () {
    var table = const StationTable().update(station('OLD1-1', t0), t0);
    final later = t0.add(const Duration(hours: 25));
    table = table.update(station('NEW1-1', later), later);
    expect(table.all.map((s) => s.displayName), ['NEW1-1']);
  });

  test('capped at maxStations, the least recently heard go first', () {
    var table = const StationTable();
    for (var i = 0; i < StationTable.maxStations + 10; i++) {
      final t = t0.add(Duration(seconds: i));
      table = table.update(station('S$i', t), t);
    }
    expect(table.all, hasLength(StationTable.maxStations));
    expect(table.all.any((s) => s.displayName == 'S0'), isFalse);
    expect(table.all.any((s) => s.displayName == 'S${StationTable.maxStations + 9}'), isTrue);
  });

  test('all is sorted newest first', () {
    final table = const StationTable()
        .update(station('A1', t0), t0)
        .update(station('B1', t0.add(const Duration(minutes: 5))), t0.add(const Duration(minutes: 5)));
    expect(table.all.map((s) => s.displayName), ['B1', 'A1']);
  });

  test('direct versus digipeated is kept from the latest packet', () {
    final table = const StationTable().update(station('A1', t0, via: true), t0);
    expect(table.all.single.viaDigipeater, isTrue);
  });
}
