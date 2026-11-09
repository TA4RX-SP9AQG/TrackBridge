import 'package:flutter/material.dart';

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
                    s.positionSource == PositionSource.manual ? t('Sabit konum') : t('Telefon GPS\'i'),
                    icon: s.positionSource == PositionSource.manual ? Icons.home_outlined : Icons.my_location_rounded,
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
                _row(context, t('Konum kaynağı'), s.positionSource == PositionSource.manual ? 'Sabit konum' : 'Telefon GPS\'i'),
                const Divider(),
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
