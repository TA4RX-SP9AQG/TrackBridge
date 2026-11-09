import 'dart:async';

import 'package:flutter/material.dart';

import '../core/smart_beacon.dart';
import '../core/time_format.dart';
import '../state/app_controller.dart';
import '../state/auto_beacon.dart';
import '../state/models.dart';
import '../state/phone_fix_feed.dart';
import 'app_theme.dart';
import 'widgets/ui_kit.dart';
import '../l10n/app_strings.dart';

/// Switch, settings and status for automatic beacons.
class AutoBeaconCard extends StatefulWidget {
  const AutoBeaconCard({super.key, required this.controller, required this.auto, required this.feed});

  final AppController controller;
  final AutoBeaconController auto;
  final PhoneFixFeed feed;

  @override
  State<AutoBeaconCard> createState() => _AutoBeaconCardState();
}

class _AutoBeaconCardState extends State<AutoBeaconCard> {
  static const List<int> _intervalMinutes = [1, 2, 5, 10, 15, 30, 60];

  AutoBeaconMode _mode = AutoBeaconMode.interval;
  int _minutes = 10;
  String _profile = t('Yürüyüş');
  bool _starting = false;

  AutoBeaconController get _auto => widget.auto;

  @override
  void initState() {
    super.initState();
    _auto.addListener(_stopFeedWhenOff);
  }

  @override
  void dispose() {
    _auto.removeListener(_stopFeedWhenOff);
    super.dispose();
  }

  void _stopFeedWhenOff() {
    if (!_auto.running) unawaited(widget.feed.stop());
  }

  bool get _phoneSource => widget.controller.settings.positionSource == PositionSource.phone;

  Future<bool> _confirm() async {
    final s = widget.controller.settings;
    final exact = s.ambiguity == 0;
    final what = _mode == AutoBeaconMode.interval
        ? t('her {minutes} dakikada bir', {'minutes': _minutes})
        : t('hareketinize göre (hızlandıkça ve dönüşlerde daha sık)');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.cell_tower_rounded, color: scheme.tertiary, size: 32),
          title: Text(t('Otomatik beacon başlatılsın mı?')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Konumunuz {what} telsizle yayınlanacak. İnternete düşerse herkese açık görünür.', {'what': what})),
            const SizedBox(height: Gaps.m),
            if (exact)
              Text(
                t('Konum belirsizliği 0: tam konumunuz yayınlanır.'),
                style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
              )
            else
              Text(t('Konum belirsizliği {v1}: gizlenen basamaklar yayınlanmaz.', {'v1': s.ambiguity})),
            const SizedBox(height: Gaps.m),
            Text(
              t('Tracker bağlantısı koparsa durur ve kendiliğinden yeniden başlamaz. Uygulama kapanınca da kapalı açılır.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Vazgeç'))),
            FilledButton.icon(
              style: transmitButtonStyle(context),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(t('Başlat')),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm() || !mounted) return;
    setState(() => _starting = true);
    try {
      if (_phoneSource) {
        final problem = await widget.feed.start(_auto.onFix);
        if (problem != null) {
          messenger.showSnackBar(SnackBar(content: Text(problem)));
          return;
        }
        // Wait a little for the first GPS fix.
        for (var i = 0; i < 30 && _auto.lastFix == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      final config = _mode == AutoBeaconMode.interval
          ? AutoBeaconConfig.interval(Duration(minutes: _minutes))
          : AutoBeaconConfig.smart(SmartBeaconParams.presets[_profile]!);
      final result = await _auto.start(config);
      if (result != StartResult.started) {
        await widget.feed.stop();
        messenger.showSnackBar(SnackBar(content: Text(_explain(result))));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String _explain(StartResult r) => switch (r) {
        StartResult.started => '',
        StartResult.notConnected => t('Önce Bağlantı sekmesinden tracker\'a bağlanın.'),
        StartResult.noPosition => _phoneSource
            ? t('Güncel GPS konumu alınamadı. Açık havada, uygulama açıkken tekrar deneyin.')
            : t('Ayarlar\'dan sabit konum girin.'),
        StartResult.badConfig => t('Ayarlar geçersiz (aralık en az 1 dakika olmalı).'),
        StartResult.needsPhoneGps => t('Akıllı mod hareket gerektirir: Ayarlar\'da konum kaynağı olarak "Telefon GPS"ini seçin.'),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_auto, widget.controller]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final running = _auto.running;
        final connected = widget.controller.linkInfo.isConnected;
        final last = _auto.lastSent;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionHeader(t('Otomatik beacon'), subtitle: t('Her oturumda elle başlatılır'), trailing: StatusPill(
            running ? t('Açık') : t('Kapalı'),
            icon: running ? Icons.sensors_rounded : Icons.sensors_off_rounded,
            tone: running ? PillTone.accent : PillTone.neutral,
          )),
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SegmentedButton<AutoBeaconMode>(
                expandedInsets: EdgeInsets.zero,
                segments: [
                  ButtonSegment(value: AutoBeaconMode.interval, label: Text(t('Sabit aralık')), icon: Icon(Icons.timer_outlined)),
                  ButtonSegment(value: AutoBeaconMode.smart, label: Text(t('Akıllı')), icon: Icon(Icons.directions_walk_rounded)),
                ],
                selected: {_mode},
                onSelectionChanged: running ? null : (v) => setState(() => _mode = v.first),
              ),
              const SizedBox(height: Gaps.l),
              if (_mode == AutoBeaconMode.interval)
                DropdownButtonFormField<int>(
                  initialValue: _minutes,
                  decoration: InputDecoration(labelText: t('Aralık')),
                  items: [for (final m in _intervalMinutes) DropdownMenuItem(value: m, child: Text(t('{m} dakika', {'m': m})))],
                  onChanged: running ? null : (v) => setState(() => _minutes = v ?? _minutes),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _profile,
                  decoration: InputDecoration(labelText: t('Profil')),
                  items: [for (final p in SmartBeaconParams.presets.keys) DropdownMenuItem(value: p, child: Text(t(p)))],
                  onChanged: running ? null : (v) => setState(() => _profile = v ?? _profile),
                ),
                const SizedBox(height: Gaps.s),
                Text(
                  t('Hızınıza göre sıklaşır, duruyorsanız seyrekleşir, dönüşlerde hemen yayınlar. Telefon GPS\'i gerekir. Çalışırken kalıcı bir konum bildirimi gösterir ve ekran kapalıyken de sürer.'),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: Gaps.l),
              if (running)
                OutlinedButton.icon(
                  onPressed: () => _auto.stop(),
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(t('Durdur')),
                )
              else
                FilledButton.icon(
                  style: transmitButtonStyle(context),
                  onPressed: connected && !_starting ? _start : null,
                  icon: _starting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(t('Otomatik beacon\'ı başlat')),
                ),
              const SizedBox(height: Gaps.m),
              Text(_auto.status, style: theme.textTheme.bodyMedium),
              if (last != null)
                Text(t('Son beacon: {v1}', {'v1': formatClockSeconds(last)}),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              if (_auto.log.isNotEmpty) ...[
                const Divider(height: Gaps.xl),
                Text(t('Son otomatik beaconlar'), style: theme.textTheme.titleSmall),
                const SizedBox(height: Gaps.xs),
                for (final e in _auto.log.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${formatClockSeconds(e.time)}  ${e.reason}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ]),
          ),
        ]);
      },
    );
  }
}
