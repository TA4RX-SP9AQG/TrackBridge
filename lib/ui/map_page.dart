import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/aprs.dart';
import '../core/navigation_links.dart';
import '../core/tile_url.dart';
import '../state/app_controller.dart';
import '../state/station_table.dart';
import 'messages_page.dart';
import 'station_sheet.dart';
import 'symbol_widget.dart';

/// Map of the stations, objects and items the tracker heard over the radio.
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.controller,
    this.launcher = const UrlLauncherAdapter(),
    this.tileProvider,
    this.now,
  });

  final AppController controller;
  final UriLauncher launcher;

  /// Replaces the network tile provider (tests).
  final TileProvider? tileProvider;
  final DateTime Function()? now;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const String _userAgentPackage = 'com.sp9aqg.trackbridge';

  final MapController _map = MapController();
  bool _fitted = false;
  String? _selectedId;

  AppController get _c => widget.controller;
  DateTime _now() => (widget.now ?? DateTime.now)();

  OwnPoint? get _own {
    final s = _c.settings;
    final lat = s.manualLat;
    final lon = s.manualLon;
    return lat == null || lon == null ? null : OwnPoint(lat, lon);
  }

  List<LatLng> _points(List<Station> stations) => [
        for (final s in stations) LatLng(s.position.lat, s.position.lon),
        if (_own != null) LatLng(_own!.lat, _own!.lon),
      ];

  void _fitAll(List<LatLng> points) {
    if (points.isEmpty) return;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(56, 96, 56, 96),
      maxZoom: 13,
    ));
  }

  void _fitOnceWhenStationsAppear(List<Station> stations) {
    if (_fitted || stations.isEmpty) return;
    _fitted = true;
    final points = _points(stations);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitAll(points);
    });
  }

  Future<void> _open(Station station) async {
    setState(() => _selectedId = station.id);
    await showStationSheet(
      context,
      station: station,
      launcher: widget.launcher,
      now: _now(),
      own: _own,
      onMessage: _canMessage(station) ? () => _message(station) : null,
    );
    if (mounted) setState(() => _selectedId = null);
  }

  bool _canMessage(Station station) => isUsableCallsign(station.owner);

  void _message(Station station) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChatPage(controller: _c, peer: normalizeCallsign(station.owner)),
    ));
  }

  Marker _stationMarker(Station s) {
    final selected = s.id == _selectedId;
    final scheme = Theme.of(context).colorScheme;
    return Marker(
      point: LatLng(s.position.lat, s.position.lon),
      width: 96,
      height: 72,
      child: GestureDetector(
        key: ValueKey('station_${s.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(s),
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: selected
                ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.primary, width: 3))
                : null,
            child: AprsSymbolIcon(table: s.position.symbolTable, code: s.position.symbolCode, size: 36),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                s.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final stations = _c.stations;
        _fitOnceWhenStationsAppear(stations);
        final url = _c.settings.tileUrl;
        final own = _own;
        final scheme = Theme.of(context).colorScheme;
        final first = stations.isEmpty ? null : stations.first.position;
        return Scaffold(
          appBar: AppBar(
            title: Text('Harita (${stations.length} istasyon)'),
            actions: [
              IconButton(
                tooltip: 'Tümünü göster',
                icon: const Icon(Icons.zoom_out_map),
                onPressed: () => _fitAll(_points(stations)),
              ),
            ],
          ),
          body: Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: first != null
                    ? LatLng(first.lat, first.lon)
                    : own != null
                        ? LatLng(own.lat, own.lon)
                        : const LatLng(50.0, 15.0),
                initialZoom: first != null || own != null ? 9 : 4,
                minZoom: 2,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate: url,
                  userAgentPackageName: _userAgentPackage,
                  tileProvider: widget.tileProvider,
                ),
                MarkerLayer(markers: [for (final s in stations) _stationMarker(s)]),
                if (own != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(own.lat, own.lon),
                      width: 40,
                      height: 40,
                      child: Icon(Icons.home, key: const ValueKey('own_marker'), color: scheme.primary, size: 32),
                    ),
                  ]),
                SimpleAttributionWidget(
                  source: Text(isOpenStreetMapUrl(url)
                      ? 'OpenStreetMap contributors'
                      : 'harita: ${tileHost(url) ?? 'özel karo sunucusu'}'),
                ),
              ],
            ),
            if (stations.isEmpty)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Card(
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Henüz konumlu paket duyulmadı. Tracker\'a bağlıyken telsizle duyduğu konumlar burada görünür '
                      '(yalnızca telsizle duyulanlar; internet beslemesi yok).',
                    ),
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }
}
