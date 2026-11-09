import 'package:flutter/material.dart';

import '../core/aprs_position.dart';
import '../core/geo.dart';
import '../core/navigation_links.dart';
import '../core/symbols.dart';
import '../core/time_format.dart';
import '../state/station_table.dart';
import 'app_theme.dart';
import 'symbol_widget.dart';
import 'widgets/ui_kit.dart';
import '../l10n/app_strings.dart';

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
      messenger.showSnackBar(SnackBar(content: Text(t('Harita/navigasyon uygulaması açılamadı.'))));
    }
  }

  Future<void> _openElsewhere(BuildContext context) async {
    final p = station.position;
    final messenger = ScaffoldMessenger.of(context);
    if (!await openInMapApp(p.lat, p.lon, station.displayName, launcher: launcher)) {
      messenger.showSnackBar(SnackBar(content: Text(t('Harita uygulaması açılamadı.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = station.position;
    final symbol = resolveSymbol(p.symbolTable, p.symbolCode);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ownPoint = own;
    final rows = <(String, String)>[
      (t('Konum'), _positionText(p)),
      if (ownPoint != null)
        (
          t('Mesafe'),
          t('{v1} · {v2} yönünde', {'v1': formatDistance(distanceKm(ownPoint.lat, ownPoint.lon, p.lat, p.lon)), 'v2': compassPoint(bearingDegrees(ownPoint.lat, ownPoint.lon, p.lat, p.lon))}),
        ),
      if (p.speedKmh != null || p.courseDeg != null) (t('Hız / yön'), _motionText(p)),
      if (p.altitudeM != null) (t('Yükseklik'), '${p.altitudeM!.round()} m'),
      (t('Son duyulma'), t('{age} · {clock} · {n} paket', {'age': formatAge(now.difference(station.lastHeard)), 'clock': formatClock(station.lastHeard), 'n': station.packetCount})),
      (t('Nasıl duyuldu'), station.viaDigipeater ? t('Digipeater üzerinden: {v1}', {'v1': station.path}) : t('Doğrudan duyuldu')),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.l)),
              alignment: Alignment.center,
              child: AprsSymbolIcon(table: p.symbolTable, code: p.symbolCode, size: 46),
            ),
            const SizedBox(width: Gaps.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(station.displayName, style: theme.textTheme.titleLarge),
                Text(
                  [
                    symbol?.info.name ?? '${p.symbolTable}${p.symbolCode}',
                    if (station.isObject) t('nesne (sahibi: {owner})', {'owner': station.owner}),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: Gaps.l),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Gaps.l),
            decoration: BoxDecoration(
              // The dark sheet itself is surfaceContainerHigh, so the comment box must be a step lighter.
              color: scheme.brightness == Brightness.dark ? scheme.surfaceContainerHighest : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Radii.l),
            ),
            child: p.comment.isEmpty
                ? Text(t('Yorum yok'), style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant))
                : SelectableText(p.comment, style: theme.textTheme.bodyLarge),
          ),
          const SizedBox(height: Gaps.m),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.xs),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(),
                _InfoRow(rows[i].$1, rows[i].$2),
              ],
            ]),
          ),
          const SizedBox(height: Gaps.l),
          FilledButton.icon(
            onPressed: () => _directions(context),
            icon: const Icon(Icons.navigation_rounded),
            label: Text(t('Yol tarifi')),
          ),
          if (onMessage != null) ...[
            const SizedBox(height: Gaps.s),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onMessage!();
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: Text(t('Mesaj gönder')),
            ),
          ],
          const SizedBox(height: Gaps.xs),
          TextButton.icon(
            onPressed: () => _openElsewhere(context),
            icon: const Icon(Icons.map_outlined),
            label: Text(t('Başka uygulamada aç')),
          ),
        ]),
      ),
    );
  }

  String _positionText(AprsPosition p) {
    final text = '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}';
    if (p.ambiguity == 0) return text;
    const sizes = ['', '~200 m', '~2 km', '~20 km', '~200 km'];
    return t('{text} (belirsiz konum, {size})', {'text': text, 'size': sizes[p.ambiguity]});
  }

  String _motionText(AprsPosition p) {
    final parts = <String>[
      if (p.speedKmh != null) t('{v1} km/sa', {'v1': p.speedKmh!.toStringAsFixed(1)}),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gaps.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 108,
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
      ]),
    );
  }
}
