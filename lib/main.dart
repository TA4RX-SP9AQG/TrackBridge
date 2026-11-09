import 'dart:async';

import 'package:flutter/material.dart';

import 'background/background_coordinator.dart';
import 'background/background_service.dart';
import 'background/heartbeat.dart';
import 'background/native_bridge.dart';
import 'background/notification_background_service.dart';
import 'ble/reactive_tracker_link.dart';
import 'state/app_controller.dart';
import 'state/auto_beacon.dart';
import 'state/phone_fix_feed.dart';
import 'state/message_store.dart';
import 'state/settings_store.dart';
import 'ui/app_theme.dart';
import 'ui/background_section.dart';
import 'ui/home_page.dart';
import 'ui/permissions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 11 and older only deliver BLE scan results while location is on.
  final needsLocation = await androidSdkInt() < 31;
  // Message notifications (phone and Android Auto) are built by native code; the bridge connects them.
  final bridge = NativeMessageBridge();
  final controller = AppController(
    link: ReactiveTrackerLink(requireLocationServices: needsLocation),
    store: PrefsSettingsStore(),
    notifier: bridge,
    messageStore: PrefsMessageStore(),
  );
  await controller.init();
  bridge.attach(controller);

  // The Flutter engine is created by TrackBridgeApplication and outlives the activity, so this
  // runs once per process. The heartbeat starts right away so the Bağlantı tab can show whether
  // Dart kept running while the app was in the background.
  final heartbeat = Heartbeat(store: PrefsHeartbeatStore());
  await heartbeat.start();
  final service = ServiceSwitchController(NotificationBackgroundService(), preflight: ensureBlePermissions);
  BackgroundCoordinator(link: controller.link, service: service, onForeground: controller.setAppForeground).attach();

  // Automatic beacons: always off at start. The timer only drives it while the user has switched it on.
  final auto = AutoBeaconController(app: controller);
  Timer.periodic(const Duration(seconds: 5), (_) => unawaited(auto.tick()));

  runApp(TrackBridgeApp(
    controller: controller,
    background: BackgroundTools(heartbeat: heartbeat, service: service),
    auto: auto,
    feed: GeolocatorFeed(),
  ));
}

class TrackBridgeApp extends StatelessWidget {
  const TrackBridgeApp({super.key, required this.controller, this.background, this.auto, this.feed});

  final AppController controller;
  final BackgroundTools? background;
  final AutoBeaconController? auto;
  final PhoneFixFeed? feed;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomePage(controller: controller, background: background, auto: auto, feed: feed),
    );
  }
}
