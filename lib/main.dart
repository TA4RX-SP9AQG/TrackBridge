import 'package:flutter/material.dart';

import 'ble/reactive_tracker_link.dart';
import 'state/app_controller.dart';
import 'state/settings_store.dart';
import 'ui/app_theme.dart';
import 'ui/home_page.dart';
import 'ui/permissions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 11 and older only deliver BLE scan results while location is on.
  final needsLocation = await androidSdkInt() < 31;
  final controller = AppController(
    link: ReactiveTrackerLink(requireLocationServices: needsLocation),
    store: PrefsSettingsStore(),
  );
  await controller.init();
  runApp(TrackBridgeApp(controller: controller));
}

class TrackBridgeApp extends StatelessWidget {
  const TrackBridgeApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrackBridge',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: HomePage(controller: controller),
    );
  }
}
