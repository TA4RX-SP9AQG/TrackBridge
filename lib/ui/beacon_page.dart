import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../core/symbols.dart';
import '../state/models.dart';
import 'symbol_widget.dart';
import 'confirm_transmit.dart';

/// Approximate size of the blanked square for each ambiguity level.
const List<String> ambiguityLabels = <String>['~20 m', '~200 m', '~2 km', '~20 km', '~200 km'];

class BeaconPage extends StatefulWidget {
  const BeaconPage({super.key, required this.controller});

  final AppController controller;

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
        return Scaffold(
          appBar: AppBar(title: const Text('Beacon')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _row('Çağrı işareti', s.callsign.isEmpty ? '(ayarlanmadı)' : s.callsign),
                  _row('Konum kaynağı', s.positionSource == PositionSource.manual ? 'Sabit konum' : 'Telefon GPS\'i'),
                  _row('Konum belirsizliği', '${s.ambiguity}  (${ambiguityLabels[s.ambiguity]})'),
                  _row('Yol (path)', s.path.isEmpty ? '(boş)' : s.path),
                  _row('Yorum', s.comment),
                  _symbolRow(s),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Belirsizlik > 0 iken gizlenen basamaklar pakete hiç girmez; tam konumunuz yayınlanmaz.'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: connected && !_busy ? _send : null,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cell_tower),
              label: const Text('Beacon hazırla ve gönder'),
            ),
            if (!connected)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Önce Bağlantı sekmesinden tracker\'a bağlanın.')),
          ]),
        );
      },
    );
  }

  Widget _symbolRow(AppSettings s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const SizedBox(width: 130, child: Text('Simge')),
          AprsSymbolIcon(table: s.symbolTable, code: s.symbol, size: 32),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              resolveSymbol(s.symbolTable, s.symbol)?.info.name ?? '${s.symbolTable}${s.symbol}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
