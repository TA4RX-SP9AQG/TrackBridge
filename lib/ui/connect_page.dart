import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/tracker_link.dart';
import '../core/packet_summary.dart';
import '../core/time_format.dart';
import '../state/app_controller.dart';
import '../state/models.dart';
import 'app_theme.dart';
import 'brand_lockup.dart';
import 'permissions.dart';
import 'widgets/ui_kit.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  static const Duration _scanDuration = Duration(seconds: 12);
  static const int _shownPackets = 40;

  final Map<String, FoundTracker> _found = <String, FoundTracker>{};
  StreamSubscription<FoundTracker>? _scanSub;
  Timer? _scanTimer;
  bool _scanning = false;
  String? _scanError;

  AppController get _c => widget.controller;

  Future<void> _startScan() async {
    final granted = await ensureBlePermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() => _scanError = 'Bluetooth izni verilmedi. Uygulama ayarlarından izin verin.');
      return;
    }
    await _stopScan();
    setState(() {
      _found.clear();
      _scanError = null;
      _scanning = true;
    });
    _scanSub = _c.link.scan().listen(
      (t) => setState(() => _found[t.id] = t),
      onError: (Object e) => setState(() {
        _scanError = 'Tarama hatası: $e';
        _scanning = false;
      }),
    );
    _scanTimer = Timer(_scanDuration, _stopScan);
  }

  Future<void> _stopScan() async {
    _scanTimer?.cancel();
    await _scanSub?.cancel();
    _scanSub = null;
    if (mounted && _scanning) setState(() => _scanning = false);
  }

  Future<void> _connect(FoundTracker t) async {
    await _stopScan();
    await _c.connectTo(t);
  }

  Future<void> _connectLast() async {
    if (!await ensureBlePermissions() || !mounted) return;
    await _c.connectTo(FoundTracker(
      id: _c.settings.lastDeviceId!,
      name: _c.settings.lastDeviceName ?? 'Son cihaz',
      rssi: 0,
    ));
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_scanSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final info = _c.linkInfo;
        final found = _found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
        final heard = _c.heard.take(_shownPackets).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(Gaps.l, Gaps.s, Gaps.l, Gaps.xl),
          children: [
            const Center(child: BrandLockup(height: 96)),
            _AdapterBanner(stream: _c.link.adapterState),
            _LinkHero(info: info),
            if (info.error != null && info.status != LinkStatus.connected)
              Padding(
                padding: const EdgeInsets.only(top: Gaps.s),
                child: StatusPill(info.error!, icon: Icons.warning_amber_rounded, tone: PillTone.warning),
              ),
            const SizedBox(height: Gaps.l),
            FilledButton.icon(
              onPressed: _scanning ? _stopScan : _startScan,
              icon: Icon(_scanning ? Icons.stop_rounded : Icons.search_rounded),
              label: Text(_scanning ? 'Taramayı durdur' : 'Tracker ara'),
            ),
            if (info.status != LinkStatus.disconnected) ...[
              const SizedBox(height: Gaps.s),
              OutlinedButton.icon(
                onPressed: _c.disconnect,
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Bağlantıyı kes'),
              ),
            ] else if (_c.settings.lastDeviceId != null) ...[
              const SizedBox(height: Gaps.s),
              FilledButton.tonalIcon(
                onPressed: _connectLast,
                icon: const Icon(Icons.history_rounded),
                label: Text('Son cihaz: ${_c.settings.lastDeviceName ?? ''}'),
              ),
            ],
            if (_scanError != null)
              Padding(
                padding: const EdgeInsets.only(top: Gaps.m),
                child: StatusPill(_scanError!, icon: Icons.error_outline_rounded, tone: PillTone.error),
              ),
            if (_scanning)
              const Padding(
                padding: EdgeInsets.only(top: Gaps.m),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(Radii.s)),
                  child: LinearProgressIndicator(minHeight: 6),
                ),
              ),
            if (found.isNotEmpty) ...[
              const SectionHeader('Bulunan cihazlar'),
              for (final t in found)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gaps.s),
                  child: _DeviceTile(tracker: t, onTap: () => _connect(t)),
                ),
            ],
            SectionHeader(
              'Duyulan paketler',
              subtitle: heard.isEmpty ? null : '${heard.length} paket · telsizle duyulanlar',
            ),
            if (heard.isEmpty)
              const SurfaceCard(
                child: EmptyState(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Henüz paket yok',
                  message: 'Tracker\'a bağlıyken telsizle duyduğu her şey burada görünür.',
                ),
              )
            else
              SurfaceCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (var i = 0; i < heard.length; i++) ...[
                    if (i > 0) const Divider(),
                    _PacketRow(packet: heard[i]),
                  ],
                ]),
              ),
          ],
        );
      },
    );
  }
}

class _AdapterBanner extends StatelessWidget {
  const _AdapterBanner({required this.stream});

  final Stream<AdapterState> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdapterState>(
      stream: stream,
      builder: (context, snapshot) {
        final text = switch (snapshot.data) {
          AdapterState.off => 'Telefonun Bluetooth\'u kapalı. Açın.',
          AdapterState.unauthorized => 'Bluetooth izni yok. Uygulama ayarlarından izin verin.',
          AdapterState.unavailable => 'Bu telefon Bluetooth LE desteklemiyor.',
          _ => null,
        };
        if (text == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Container(
          margin: const EdgeInsets.only(bottom: Gaps.m),
          padding: const EdgeInsets.all(Gaps.l),
          decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(Radii.l)),
          child: Row(children: [
            Icon(Icons.bluetooth_disabled_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: Gaps.m),
            Expanded(child: Text(text, style: TextStyle(color: scheme.onErrorContainer))),
          ]),
        );
      },
    );
  }
}

class _LinkHero extends StatelessWidget {
  const _LinkHero({required this.info});

  final LinkInfo info;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (info.status) {
      LinkStatus.connected => (Icons.bluetooth_connected_rounded, 'Bağlı', info.deviceName ?? 'Tracker'),
      LinkStatus.connecting => (
          Icons.bluetooth_searching_rounded,
          info.attempt > 0 ? 'Yeniden bağlanıyor (${info.attempt}. deneme)' : 'Bağlanıyor...',
          info.deviceName ?? 'Tracker',
        ),
      LinkStatus.disconnected => (Icons.bluetooth_disabled_rounded, 'Bağlı değil', 'Tracker\'a bağlanmak için aramayı başlatın'),
    };
    return BrandHeroCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      muted: info.status == LinkStatus.disconnected,
      footer: info.isConnected
          ? Wrap(spacing: Gaps.s, runSpacing: Gaps.s, children: [
              HeroChip('MTU ${info.mtu}', icon: Icons.speed_rounded),
              const HeroChip('KISS servisi', icon: Icons.lan_outlined),
            ])
          : null,
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.tracker, required this.onTap});

  final FoundTracker tracker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
          child: ExcludeSemantics(child: Icon(Icons.settings_input_antenna_rounded, color: scheme.onPrimaryContainer)),
        ),
        const SizedBox(width: Gaps.l),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tracker.name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${tracker.id} · ${tracker.rssi} dBm',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      ]),
    );
  }
}

class _PacketRow extends StatelessWidget {
  const _PacketRow({required this.packet});

  final HeardPacket packet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = summarizePacket(packet.tnc2);
    final icon = switch (summary.kind) {
      PacketKind.position => Icons.place_outlined,
      PacketKind.message => Icons.chat_bubble_outline_rounded,
      PacketKind.status => Icons.info_outline_rounded,
      PacketKind.other => Icons.radio_outlined,
    };
    final label = switch (summary.kind) {
      PacketKind.position => 'konum',
      PacketKind.message => 'mesaj',
      PacketKind.status => 'durum',
      PacketKind.other => 'paket',
    };
    return Semantics(
      label: '$label, ${summary.source}, ${summary.text}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.m),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: scheme.surfaceContainerHigh, shape: BoxShape.circle),
            child: ExcludeSemantics(child: Icon(icon, size: 20, color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(width: Gaps.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(summary.source, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                if (summary.viaDigipeater) ...[
                  const SizedBox(width: Gaps.s),
                  Tooltip(
                    message: 'Digipeater üzerinden duyuldu',
                    child: Icon(Icons.repeat_rounded, size: 16, color: scheme.onSurfaceVariant, semanticLabel: 'digipeater üzerinden'),
                  ),
                ],
                const Spacer(),
                Text(
                  formatClockSeconds(packet.time),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ]),
              const SizedBox(height: Gaps.xs),
              Text(
                summary.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontFamily: 'monospace'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
