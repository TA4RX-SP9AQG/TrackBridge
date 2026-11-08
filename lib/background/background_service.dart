import 'package:flutter/foundation.dart';

enum BackgroundStartResult { started, permissionDenied, failed }

/// A foreground service with an ongoing notification. It keeps the app's
/// process (and with it the Bluetooth connection) alive while the screen is
/// off or another app is in front.
abstract class BackgroundService {
  bool get isRunning;

  Future<BackgroundStartResult> start({required String title, required String body});

  /// Changes the notification text of the running service.
  Future<void> update({required String title, required String body});

  Future<void> stop();
}

/// The user-facing switch for background operation. It never starts anything on its own.
class ServiceSwitchController extends ChangeNotifier {
  /// [preflight] runs before the service is started and returns false when a permission the
  /// service type needs (Bluetooth, for a connected device) is missing.
  ServiceSwitchController(this.service, {this.preflight});

  final BackgroundService service;
  final Future<bool> Function()? preflight;

  bool _enabled = false;
  bool _busy = false;
  String? _error;

  bool get enabled => _enabled;
  bool get busy => _busy;

  /// Why the last attempt to turn it on failed, or null.
  String? get error => _error;

  Future<void> setEnabled(bool value, {required String title, required String body}) async {
    if (_busy || value == _enabled) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      if (value) {
        if (preflight != null && !await preflight!()) {
          _enabled = false;
          _error = 'Bluetooth izni verilmedi. Servis, bağlı bir cihaz için çalıştığından Android bu izni ister.';
          return;
        }
        final result = await service.start(title: title, body: body);
        _enabled = result == BackgroundStartResult.started;
        _error = switch (result) {
          BackgroundStartResult.started => null,
          BackgroundStartResult.permissionDenied =>
            'Bildirim izni verilmedi. Arka planda çalışmak için kalıcı bir bildirim gerekir; Android ayarlarından izin verin.',
          BackgroundStartResult.failed => 'Arka plan servisi başlatılamadı.',
        };
      } else {
        await service.stop();
        _enabled = false;
      }
    } on Object catch (e) {
      _enabled = false;
      _error = 'Arka plan servisi hatası: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> updateBody({required String title, required String body}) async {
    if (!_enabled) return;
    await service.update(title: title, body: body);
  }
}
