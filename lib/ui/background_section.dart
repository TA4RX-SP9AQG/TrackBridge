import 'package:flutter/material.dart';

import '../background/background_service.dart';
import '../background/heartbeat.dart';
import '../core/time_format.dart';
import '../state/app_controller.dart';
import 'app_theme.dart';
import 'widgets/ui_kit.dart';

/// The pieces of background operation the UI needs.
class BackgroundTools {
  const BackgroundTools({required this.heartbeat, required this.service});

  final Heartbeat heartbeat;
  final ServiceSwitchController service;
}

/// Switch for background operation plus live numbers that show whether the app keeps
/// running with the screen off or after it was swiped away from the recent apps.
class BackgroundSection extends StatelessWidget {
  const BackgroundSection({super.key, required this.controller, required this.tools});

  final AppController controller;
  final BackgroundTools tools;

  /// A gap this long between 10 s beats means Android froze or starved the process.
  static const int frozenGapSeconds = 30;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([tools.heartbeat, tools.service, controller]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final hb = tools.heartbeat.snapshot;
        final previous = tools.heartbeat.previousRun;
        final frozen = hb.maxGapSeconds > frozenGapSeconds;
        final link = controller.linkInfo;
        final rows = <(String, String)>[
          ('Kalp atışı', '${hb.count}'),
          ('Son atış', hb.lastTick == null ? '-' : formatClockSeconds(hb.lastTick!)),
          ('Çalışma süresi', formatDuration(tools.heartbeat.uptime)),
          ('En uzun boşluk', '${hb.maxGapSeconds} sn'),
          ('Tracker', link.isConnected ? 'Bağlı (${link.deviceName ?? 'tracker'})' : 'Bağlı değil'),
          ('Duyulan paket', '${controller.heard.length}'),
          if (previous != null)
            (
              'Önceki oturum',
              '${previous.count} atış, son ${previous.lastTick == null ? '-' : formatClockSeconds(previous.lastTick!)}',
            ),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader('Arka plan testi', subtitle: 'Geçici: arka planda çalışmayı doğrulamak için'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Arka planda çalış'),
                subtitle: const Text(
                  'Kalıcı bir bildirim gösterir. Ekran kapalıyken ve başka uygulama öndeyken tracker bağlantısını açık tutar.',
                ),
                value: tools.service.enabled,
                onChanged: tools.service.busy
                    ? null
                    : (v) => tools.service.setEnabled(
                          v,
                          title: 'TrackBridge çalışıyor',
                          body: link.isConnected ? 'Tracker bağlı: ${link.deviceName ?? ''}' : 'Tracker bağlı değil',
                        ),
              ),
              if (tools.service.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gaps.m),
                  child: Text(tools.service.error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
                ),
              const Divider(),
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gaps.s + 2),
                  child: Row(children: [
                    Expanded(
                      child: Text(rows[i].$1, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    Text(rows[i].$2, style: theme.textTheme.titleSmall),
                  ]),
                ),
              ],
              if (frozen)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gaps.s),
                  child: StatusPill(
                    'Süreç ${hb.maxGapSeconds} sn dondu/kısıtlandı',
                    icon: Icons.warning_amber_rounded,
                    tone: PillTone.warning,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: Gaps.m),
          Text(
            'Test: anahtarı açın, Ana ekrana dönün, ekranı 10 dk kapatın, sonra uygulamayı son uygulamalardan silin ve '
            'yeniden açın. Başarılıysa kalp atışı kesintisiz sürer, "En uzun boşluk" ~10 sn kalır ve paket sayısı artar.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ]);
      },
    );
  }
}
