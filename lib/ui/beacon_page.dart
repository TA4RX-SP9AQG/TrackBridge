import 'package:flutter/material.dart';

import '../core/geo.dart';
import '../core/symbols.dart';
import '../state/app_controller.dart';
import '../state/models.dart';
import 'app_theme.dart';
import '../state/auto_beacon.dart';
import '../state/phone_fix_feed.dart';
import 'auto_beacon_card.dart';
import 'confirm_transmit.dart';
import 'symbol_widget.dart';
import 'widgets/ui_kit.dart';
import '../l10n/app_strings.dart';

/// Approximate size of the blanked square for each ambiguity level.
/// Short name of a beacon position source.
String sourceLabel(PositionSource source) => switch (source) {
      PositionSource.manual => t('Sabit konum'),
      PositionSource.phone => t('Telefon GPS'),
      PositionSource.tracker => t('Tracker GPS'),
    };

IconData sourceIcon(PositionSource source) => switch (source) {
      PositionSource.manual => Icons.home_outlined,
      PositionSource.phone => Icons.my_location_rounded,
      PositionSource.tracker => Icons.memory_rounded,
    };

const List<String> ambiguityLabels = <String>['~20 m', '~200 m', '~2 km', '~20 km', '~200 km'];

class BeaconPage extends StatefulWidget {
  const BeaconPage({super.key, required this.controller, this.auto, this.feed});

  final AppController controller;

  /// Automatic beacons; the card is hidden when null (tests).
  final AutoBeaconController? auto;
  final PhoneFixFeed? feed;

  @override
  State<BeaconPage> createState() => _BeaconPageState();
}

class _BeaconPageState extends State<BeaconPage> {
  bool _busy = false;

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final packet = await widget.controller.buildBeaconPacket();
      if (!mounted) return;
      await confirmAndTransmit(context, widget.controller, packet);
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final s = widget.controller.settings;
        final connected = widget.controller.linkInfo.isConnected;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final symbol = resolveSymbol(s.symbolTable, s.symbol);
        return Scaffold(
          appBar: AppBar(title: Text(t('Beacon'))),
          body: ListView(padding: const EdgeInsets.fromLTRB(Gaps.l, Gaps.s, Gaps.l, Gaps.xl), children: [
            SurfaceCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.l)),
                    alignment: Alignment.center,
                    child: AprsSymbolIcon(table: s.symbolTable, code: s.symbol, size: 48),
                  ),
                  const SizedBox(width: Gaps.l),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.callsign.isEmpty ? t('(çağrı işareti yok)') : s.callsign, style: theme.textTheme.titleLarge),
                      Text(
                        symbol?.info.name ?? '${s.symbolTable}${s.symbol}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: Gaps.l),
                Wrap(spacing: Gaps.s, runSpacing: Gaps.s, children: [
                  StatusPill(
                    sourceLabel(s.positionSource),
                    icon: sourceIcon(s.positionSource),
                  ),
                  StatusPill(
                    s.ambiguity == 0 ? t('Tam konum') : t('Belirsizlik {n} · {range}', {'n': s.ambiguity, 'range': ambiguityLabels[s.ambiguity]}),
                    icon: s.ambiguity == 0 ? Icons.location_on_outlined : Icons.blur_on_rounded,
                    tone: s.ambiguity == 0 ? PillTone.warning : PillTone.success,
                  ),
                ]),
              ]),
            ),
            SectionHeader(t('Paket ayrıntıları')),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.s),
              child: Column(children: [
                _row(context, t('Çağrı işareti'), s.callsign.isEmpty ? t('(ayarlanmadı)') : s.callsign),
                const Divider(),
                _row(context, t('Konum kaynağı'), sourceLabel(s.positionSource)),
                const Divider(),
                if (s.positionSource == PositionSource.tracker) ...[
                  _row(context, t('Tracker GPS konumu'), _trackerFixText()),
                  const Divider(),
                ],
                _row(context, t('Konum belirsizliği'), '${s.ambiguity}  (${ambiguityLabels[s.ambiguity]})'),
                const Divider(),
                _row(context, t('Yol (path)'), s.path.isEmpty ? t('(boş)') : s.path),
                const Divider(),
                _row(context, t('Yorum'), s.comment.isEmpty ? t('(boş)') : s.comment),
              ]),
            ),
            const SizedBox(height: Gaps.m),
            Container(
              padding: const EdgeInsets.all(Gaps.l),
              decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(Radii.l)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ExcludeSemantics(child: Icon(Icons.privacy_tip_outlined, color: scheme.onSecondaryContainer)),
                const SizedBox(width: Gaps.m),
                Expanded(
                  child: Text(
                    t('Belirsizlik > 0 iken gizlenen basamaklar pakete hiç girmez; tam konumunuz yayınlanmaz.'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer),
                  ),
                ),
              ]),
            ),
            if (widget.auto != null && widget.feed != null)
              AutoBeaconCard(controller: widget.controller, auto: widget.auto!, feed: widget.feed!),
            const SizedBox(height: Gaps.xl),
            FilledButton.icon(
              style: transmitButtonStyle(context),
              onPressed: connected && !_busy ? _send : null,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cell_tower_rounded),
              label: Text(t('Beacon hazırla ve gönder')),
            ),
            if (!connected)
              Padding(
                padding: EdgeInsets.only(top: Gaps.m),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    t('Önce Bağlantı sekmesinden tracker\'a bağlanın.'),
                    icon: Icons.bluetooth_disabled_rounded,
                    tone: PillTone.warning,
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  /// When the tracker's own GPS position was last heard (or that it was not, yet).
  String _trackerFixText() {
    final fix = widget.controller.trackerFix;
    if (fix == null) return t('henüz alınmadı');
    final age = DateTime.now().difference(fix.time);
    final text = t('{v1} ({v2})', {'v1': formatAge(age), 'v2': '${fix.lat.toStringAsFixed(4)}, ${fix.lon.toStringAsFixed(4)}'});
    return widget.controller.freshTrackerPoint == null ? t('{v1} - eski, kullanılmaz', {'v1': text}) : text;
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gaps.m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 132,
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Expanded(child: Text(value, style: theme.textTheme.titleSmall)),
      ]),
    );
  }
}
