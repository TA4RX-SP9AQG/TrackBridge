import 'package:flutter/material.dart';

import '../core/aprs_position.dart';
import '../core/geo.dart';
import '../core/navigation_links.dart';
import '../core/symbols.dart';
import '../state/station_table.dart';
import 'symbol_widget.dart';

/// Our own position (from settings) for distance and bearing, or null.
class OwnPoint {
  const OwnPoint(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// Opens the details of [station]: comment, speed/course/altitude, distance,
/// how it was heard, and buttons for directions and messaging.
Future<void> showStationSheet(
  BuildContext context, {
  required Station station,
  required UriLauncher launcher,
  required DateTime now,
  OwnPoint? own,
  VoidCallback? onMessage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StationSheet(station: station, launcher: launcher, now: now, own: own, onMessage: onMessage),
  );
}

class StationSheet extends StatelessWidget {
  const StationSheet({
    super.key,
    required this.station,
    required this.launcher,
    required this.now,
    this.own,
    this.onMessage,
  });

  final Station station;
  final UriLauncher launcher;
  final DateTime now;
  final OwnPoint? own;
  final VoidCallback? onMessage;

  Future<void> _directions(BuildContext context) async {
    final p = station.position;
    final messenger = ScaffoldMessenger.of(context);
    final result = await openNavigation(p.lat, p.lon, station.displayName, launcher: launcher);
    if (result == NavigationResult.failed) {
      messenger.showSnackBar(const SnackBar(content: Text('Harita/navigasyon uygulaması açılamadı.')));
    }
  }

  Future<void> _openElsewhere(BuildContext context) async {
    final p = station.position;
    final messenger = ScaffoldMessenger.of(context);
    if (!await openInMapApp(p.lat, p.lon, station.displayName, launcher: launcher)) {
      messenger.showSnackBar(const SnackBar(content: Text('Harita uygulaması açılamadı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = station.position;
    final symbol = resolveSymbol(p.symbolTable, p.symbolCode);
    final textTheme = Theme.of(context).textTheme;
    final ownPoint = own;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            AprsSymbolIcon(table: p.symbolTable, code: p.symbolCode, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(station.displayName, style: textTheme.titleLarge),
                Text(
                  [
                    symbol?.info.name ?? '${p.symbolTable}${p.symbolCode}',
                    if (station.isObject) 'nesne (sahibi: ${station.owner})',
                  ].join(' · '),
                  style: textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (p.comment.isEmpty)
            Text('Yorum yok', style: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic))
          else
            SelectableText(p.comment, style: textTheme.bodyLarge),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _InfoRow('Konum', _positionText(p)),
          if (ownPoint != null)
            _InfoRow(
              'Mesafe',
              () {
                final km = distanceKm(ownPoint.lat, ownPoint.lon, p.lat, p.lon);
                final bearing = bearingDegrees(ownPoint.lat, ownPoint.lon, p.lat, p.lon);
                return '${formatDistance(km)} · ${compassPoint(bearing)} yönünde';
              }(),
            ),
          if (p.speedKmh != null || p.courseDeg != null)
            _InfoRow('Hız / yön', _motionText(p)),
          if (p.altitudeM != null) _InfoRow('Yükseklik', '${p.altitudeM!.round()} m'),
          _InfoRow('Son duyulma', '${formatAge(now.difference(station.lastHeard))} · ${station.packetCount} paket'),
          _InfoRow('Nasıl duyuldu', station.viaDigipeater ? 'Digipeater üzerinden: ${station.path}' : 'Doğrudan duyuldu'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => _directions(context),
              icon: const Icon(Icons.navigation),
              label: const Text('Yol tarifi'),
            ),
            if (onMessage != null)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  onMessage!();
                },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Mesaj gönder'),
              ),
            TextButton.icon(
              onPressed: () => _openElsewhere(context),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Başka uygulamada aç'),
            ),
          ]),
        ]),
      ),
    );
  }

  String _positionText(AprsPosition p) {
    final text = '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';
    if (p.ambiguity == 0) return text;
    const sizes = ['', '~200 m', '~2 km', '~20 km', '~200 km'];
    return '$text (belirsiz konum, ${sizes[p.ambiguity]})';
  }

  String _motionText(AprsPosition p) {
    final parts = <String>[
      if (p.speedKmh != null) '${p.speedKmh!.toStringAsFixed(1)} km/sa',
      if (p.courseDeg != null) '${p.courseDeg}° (${compassPoint(p.courseDeg!.toDouble())})',
    ];
    return parts.join(' · ');
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value)),
        ]),
      );
}
