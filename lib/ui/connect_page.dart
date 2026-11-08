import 'dart:async';

import 'package:flutter/material.dart';

import '../ble/tracker_link.dart';
import '../state/app_controller.dart';
import 'brand_lockup.dart';
import 'permissions.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  static const Duration _scanDuration = Duration(seconds: 12);

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
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Center(child: BrandLockup(height: 112)),
            _AdapterBanner(stream: _c.link.adapterState),
            _StatusCard(info: info),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _scanning ? _stopScan : _startScan,
                icon: Icon(_scanning ? Icons.stop : Icons.search),
                label: Text(_scanning ? 'Taramayı durdur' : 'Tracker ara'),
              ),
              if (info.status != LinkStatus.disconnected)
                OutlinedButton.icon(
                  onPressed: _c.disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Bağlantıyı kes'),
                )
              else if (_c.settings.lastDeviceId != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    if (!await ensureBlePermissions() || !mounted) return;
                    await _c.connectTo(FoundTracker(
                      id: _c.settings.lastDeviceId!,
                      name: _c.settings.lastDeviceName ?? 'Son cihaz',
                      rssi: 0,
                    ));
                  },
                  icon: const Icon(Icons.history),
                  label: Text('Son cihaz: ${_c.settings.lastDeviceName ?? ''}'),
                ),
            ]),
            if (_scanError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_scanError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (_scanning) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            for (final t in (_found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi))))
              ListTile(
                leading: const Icon(Icons.settings_input_antenna),
                title: Text(t.name),
                subtitle: Text('${t.id}   ${t.rssi} dBm'),
                onTap: () => _connect(t),
              ),
            const Divider(height: 32),
            Text('Duyulan paketler', style: Theme.of(context).textTheme.titleMedium),
            if (_c.heard.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Henüz paket yok. Bağlıyken tracker\'ın telsizle duyduğu her şey burada görünür.'),
              ),
            for (final h in _c.heard.take(40))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${_hhmmss(h.time)}  ${h.tnc2}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
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
        return Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.info});

  final LinkInfo info;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (info.status) {
      LinkStatus.connected => (Icons.bluetooth_connected, 'Bağlı'),
      LinkStatus.connecting => (Icons.bluetooth_searching, info.attempt > 0 ? 'Yeniden bağlanıyor (${info.attempt}. deneme)' : 'Bağlanıyor...'),
      LinkStatus.disconnected => (Icons.bluetooth_disabled, 'Bağlı değil'),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text([
          if (info.deviceName != null) info.deviceName!,
          if (info.isConnected) 'MTU ${info.mtu}',
          if (info.error != null) info.error!,
        ].join('\n')),
        isThreeLine: info.error != null,
      ),
    );
  }
}
