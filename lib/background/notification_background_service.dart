import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_service.dart';

/// [BackgroundService] as an Android foreground service of type `connectedDevice`
/// (a Bluetooth tracker), started through flutter_local_notifications.
///
/// It is started **not sticky**: if Android ever kills the process the service
/// is not revived on its own, so nothing keeps running without the user knowing.
class NotificationBackgroundService implements BackgroundService {
  NotificationBackgroundService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const int notificationId = 1001;
  static const String channelId = 'trackbridge_service';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _running = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  bool get isRunning => _running;

  static const AndroidNotificationDetails _details = AndroidNotificationDetails(
    channelId,
    'Arka plan bağlantısı',
    channelDescription: 'Tracker bağlantısı arka planda açık tutulurken görünen kalıcı bildirim.',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    showWhen: false,
    category: AndroidNotificationCategory.service,
  );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      channelId,
      'Arka plan bağlantısı',
      description: 'Tracker bağlantısı arka planda açık tutulurken görünen kalıcı bildirim.',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    ));
    _initialized = true;
  }

  @override
  Future<BackgroundStartResult> start({required String title, required String body}) async {
    try {
      await _ensureInitialized();
      // Android 13+ asks the user; older versions return null and need no permission.
      final granted = await _android?.requestNotificationsPermission();
      if (granted == false) return BackgroundStartResult.permissionDenied;
      await _android?.startForegroundService(
        id: notificationId,
        title: title,
        body: body,
        notificationDetails: _details,
        startType: AndroidServiceStartType.startNotSticky,
        foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeConnectedDevice},
      );
      _running = true;
      return BackgroundStartResult.started;
    } on Object {
      _running = false;
      return BackgroundStartResult.failed;
    }
  }

  @override
  Future<void> update({required String title, required String body}) async {
    if (!_running) return;
    await _plugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: _details),
    );
  }

  @override
  Future<void> stop() async {
    await _android?.stopForegroundService();
    _running = false;
  }
}
