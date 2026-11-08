import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../state/models.dart';
import 'app_theme.dart';

/// Shows the exact packet and asks the user to confirm before it goes on the air.
Future<bool> confirmTransmit(BuildContext context, OutgoingPacket packet) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        icon: Icon(Icons.cell_tower_rounded, color: scheme.tertiary, size: 32),
        title: const Text('Yayınlansın mı?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bu paket tracker tarafından telsizle (LoRa) yayınlanacak. '
              'İnternete düşerse herkese açık görünür ve geri alınamaz.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gaps.l),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gaps.m),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.m),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: SelectableText(
                packet.tnc2,
                style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton.icon(
            style: transmitButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.cell_tower_rounded),
            label: const Text('Yayınla'),
          ),
        ],
      );
    },
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
