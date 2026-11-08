import 'package:geolocator/geolocator.dart';

/// A coordinate pair in decimal degrees.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;
}

/// Returns the current location. Injected so tests do not need a phone.
typedef PositionProvider = Future<GeoPoint> Function();

/// Reads the phone's GPS once. Throws [StateError] with a user-facing message
/// when location is off or denied.
Future<GeoPoint> readPhonePosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('Telefonun konum servisi kapalı.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw StateError('Konum izni verilmedi.');
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
  );
  return GeoPoint(position.latitude, position.longitude);
}
