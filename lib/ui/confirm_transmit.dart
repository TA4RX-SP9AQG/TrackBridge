import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../state/models.dart';

/// Shows the exact packet and asks the user to confirm before it goes on the air.
Future<bool> confirmTransmit(BuildContext context, OutgoingPacket packet) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Yayınlansın mı?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bu paket tracker tarafından telsizle (LoRa) yayınlanacak. '
              'İnternete düşerse herkese açık görünür ve geri alınamaz.'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(packet.tnc2, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yayınla')),
      ],
    ),
  );
  return result ?? false;
}

/// Confirms, transmits and reports the outcome in a snack bar.
/// Returns true when the packet was written to the tracker.
Future<bool> confirmAndTransmit(BuildContext context, AppController controller, OutgoingPacket packet) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await confirmTransmit(context, packet)) return false;
  try {
    await controller.transmit(packet);
    messenger.showSnackBar(const SnackBar(content: Text('Tracker\'a yazıldı, yayınlanıyor.')));
    return true;
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Gönderilemedi: $e')));
    return false;
  }
}
