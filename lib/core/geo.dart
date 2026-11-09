import 'dart:math' as math;
import '../l10n/app_strings.dart';

const double _earthRadiusKm = 6371.0088;

double _rad(double deg) => deg * math.pi / 180;

/// Great-circle distance in kilometres (haversine).
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusKm * math.asin(math.min(1, math.sqrt(a)));
}

/// Initial bearing from point 1 to point 2 in degrees, 0 (north) to 360.
double bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final p1 = _rad(lat1);
  final p2 = _rad(lat2);
  final dLon = _rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// "850 m", "3.4 km", "252 km".
String formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}

/// Turkish eight-point compass: K, KD, D, GD, G, GB, B, KB.
String compassPoint(double degrees) {
  final points = [t('K'), t('KD'), t('D'), t('GD'), t('G'), t('GB'), t('B'), t('KB')];
  final index = ((degrees % 360) / 45).round() % 8;
  return points[index];
}

/// "az önce", "5 dk önce", "2 sa önce", "1 gün önce".
String formatAge(Duration age) {
  if (age.inMinutes < 1) return t('az önce');
  if (age.inHours < 1) return t('{v1} dk önce', {'v1': age.inMinutes});
  if (age.inDays < 1) return t('{v1} sa önce', {'v1': age.inHours});
  return t('{v1} gün önce', {'v1': age.inDays});
}
