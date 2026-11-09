import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Asks for the permission to show notifications (Android 13+; older versions always allow them).
/// Message notifications, and with them the Android Auto integration, need it.
Future<bool> ensureNotificationPermission() async {
  if (await androidSdkInt() < 33) return true;
  return (await Permission.notification.request()).isGranted;
}

/// Android API level of this phone; 31 (Android 12) is assumed if it cannot be read.
Future<int> androidSdkInt() async {
  try {
    return (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  } on Object {
    return 31;
  }
}

/// Asks for the permissions needed to scan for and connect to the tracker.
///
/// Android 12+ (API 31) has dedicated Bluetooth permissions. Older versions
/// have none at runtime and need location for BLE scanning instead.
Future<bool> ensureBlePermissions() async {
  if (await androidSdkInt() >= 31) {
    final result = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    return result.values.every((s) => s.isGranted);
  }
  return (await Permission.locationWhenInUse.request()).isGranted;
}
