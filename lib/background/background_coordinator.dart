import 'package:flutter/widgets.dart';

import '../ble/tracker_link.dart';
import 'background_service.dart';

/// Decides what happens to the tracker connection when the app's lifecycle changes.
///
/// The Flutter engine now outlives the activity (see `TrackBridgeApplication.kt`), so
/// closing the app no longer tears the Bluetooth connection down by itself. Without
/// background mode the old behaviour is kept on purpose: closing the app disconnects.
class BackgroundCoordinator {
  BackgroundCoordinator({required this.link, required this.service});

  final TrackerLink link;
  final ServiceSwitchController service;

  AppLifecycleListener? _listener;

  /// Starts listening to the real app lifecycle.
  void attach() {
    _listener ??= AppLifecycleListener(onStateChange: (state) => handleLifecycle(state));
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }

  Future<void> handleLifecycle(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached && !service.enabled) {
      await link.disconnect();
    }
  }
}
