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
import '../l10n/app_strings.dart';

/// Map of the stations, objects and items the tracker heard over the radio.
class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    required this.controller,
    this.launcher = const UrlLauncherAdapter(),
    this.tileProvider,
    this.now,
    this.mapController,
  });

  final AppController controller;
  final UriLauncher launcher;

  /// Replaces the network tile provider (tests).
  final TileProvider? tileProvider;
  final DateTime Function()? now;

  /// Lets tests drive and inspect the camera.
  final MapController? mapController;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const String _userAgentPackage = 'com.sp9aqg.trackbridge';

  late final MapController _map = widget.mapController ?? MapController();
  bool _fitted = false;
  String? _selectedId;

  AppController get _c => widget.controller;
  DateTime _now() => (widget.now ?? DateTime.now)();

  OwnPoint? get _own {
    final point = _c.ownPosition;
    return point == null ? null : OwnPoint(point.lat, point.lon);
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

  /// The "show all" button. Says why when there is nothing to show instead of staying silent.
  void _showAll(List<Station> stations) {
    final points = _points(stations);
    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Gösterilecek konum yok: henüz konumlu paket duyulmadı ve sabit konum ayarlanmadı.')),
      ));
      return;
    }
    _fitAll(points);
  }

  static const double _minZoom = 2;
  static const double _maxZoom = 18;

  void _zoomBy(double delta) {
    final camera = _map.camera;
    final zoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom).toDouble();
    if (zoom != camera.zoom) _map.move(camera.center, zoom);
  }

  void _goToOwn() {
    final own = _own;
    if (own == null) return;
    _map.move(LatLng(own.lat, own.lon), _map.camera.zoom < 11 ? 11 : _map.camera.zoom);
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
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
            title: Text(t('Harita ({v1} istasyon)', {'v1': stations.length})),
            actions: [
              IconButton(
                tooltip: t('Tümünü göster'),
                icon: const Icon(Icons.zoom_out_map),
                onPressed: () => _showAll(stations),
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
                minZoom: _minZoom,
                maxZoom: _maxZoom,
              ),
              children: [
                TileLayer(
                  urlTemplate: url,
                  userAgentPackageName: _userAgentPackage,
                  tileProvider: widget.tileProvider,
                ),
                if (own != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(own.lat, own.lon),
                      width: 40,
                      height: 40,
                      child: Container(
                        key: const ValueKey('own_marker'),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(blurRadius: 6, color: Color(0x55000000))],
                        ),
                        child: Icon(Icons.home_rounded, color: scheme.onPrimary, size: 20),
                      ),
                    ),
                  ]),
                MarkerLayer(markers: [for (final s in stations) _stationMarker(s)]),
              ],
            ),
            Positioned(
              left: 8,
              bottom: 8,
              right: 72,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: _MapAttribution(
                  isOpenStreetMap: isOpenStreetMapUrl(url),
                  host: tileHost(url),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 48,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (own != null)
                  FloatingActionButton.small(
                    heroTag: null,
                    tooltip: t('Konumum'),
                    onPressed: _goToOwn,
                    child: const Icon(Icons.my_location),
                  ),
                if (own != null) const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  tooltip: t('Yakınlaştır'),
                  onPressed: () => _zoomBy(1),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: null,
                  tooltip: t('Uzaklaştır'),
                  onPressed: () => _zoomBy(-1),
                  child: const Icon(Icons.remove),
                ),
              ]),
            ),
            if (stations.isEmpty)
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      t('Henüz konumlu paket duyulmadı. Tracker\'a bağlıyken telsizle duyduğu konumlar burada görünür (yalnızca telsizle duyulanlar; internet beslemesi yok).'),
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

/// Map credit that wraps instead of overflowing at large text sizes.
class _MapAttribution extends StatelessWidget {
  const _MapAttribution({required this.isOpenStreetMap, required this.host});

  final bool isOpenStreetMap;
  final String? host;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isOpenStreetMap ? '© OpenStreetMap contributors' : 'harita: ${host ?? t('özel karo sunucusu')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurface),
      ),
    );
  }
}
