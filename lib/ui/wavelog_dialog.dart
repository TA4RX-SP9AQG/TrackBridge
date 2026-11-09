import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../state/app_controller.dart';
import 'app_theme.dart';
import '../l10n/app_strings.dart';

/// Shows exactly what would be sent to the Wavelog server and where, and sends it only after confirmation.
Future<void> logToWavelogWithConfirmation(BuildContext context, AppController controller, String peer) async {
  final messenger = ScaffoldMessenger.of(context);
  final preview = controller.preview(peer);
  if (preview == null) {
    messenger.showSnackBar(SnackBar(content: Text(t('Bu istasyonla mesajlaşma yok ya da çağrı işareti ayarlı değil.'))));
    return;
  }
  final host = controller.settings.wavelogConfig.host;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.menu_book_outlined),
        title: Text(t('Wavelog\'a kaydedilsin mi?')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Bu QSO {host} sunucusundaki günlüğünüze gönderilecek (telsizle yayın yapılmaz).', {'host': host}),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: Gaps.m),
            Text(t('İstasyon: {v1}', {'v1': preview.peer}), style: theme.textTheme.titleSmall),
            Text(t('İlk mesaj (UTC): {v1}  ·  {v2} mesaj', {'v1': formatClock(preview.timeUtc), 'v2': preview.messageCount})),
            const SizedBox(height: Gaps.m),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Gaps.m),
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.m)),
              child: SelectableText(preview.adif, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Vazgeç'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Kaydet'))),
        ],
      );
    },
  );
  if (ok != true) return;
  messenger.showSnackBar(SnackBar(content: Text(t('Wavelog\'a gönderiliyor...'))));
  final result = await controller.logToWavelog(peer);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.message)));
}
