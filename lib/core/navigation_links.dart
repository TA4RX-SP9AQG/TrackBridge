import 'package:url_launcher/url_launcher.dart';

/// Opens a URI in another app. The interface lets tests record what would open.
abstract class UriLauncher {
  /// Returns true when an app handled the URI. Must not throw.
  Future<bool> launch(Uri uri);
}

/// [UriLauncher] backed by the url_launcher package.
class UrlLauncherAdapter implements UriLauncher {
  const UrlLauncherAdapter();

  @override
  Future<bool> launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

String _coord(double v) => v.toStringAsFixed(6);

/// Starts turn-by-turn driving navigation in Google Maps.
Uri googleNavigationUri(double lat, double lon) => Uri.parse('google.navigation:q=${_coord(lat)},${_coord(lon)}&mode=d');

/// Shows the point in any installed map app (the user picks one).
Uri geoUri(double lat, double lon, String label) =>
    Uri.parse('geo:0,0?q=${_coord(lat)},${_coord(lon)}(${Uri.encodeComponent(label)})');

/// Google Maps directions page; opens the Maps app or the browser.
Uri webDirectionsUri(double lat, double lon) => Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${_coord(lat)},${_coord(lon)}',
      'travelmode': 'driving',
    });

enum NavigationResult { googleNavigation, mapChooser, webPage, failed }

/// Tries to give directions to the point: Google Maps navigation, then the
/// system map chooser, then the Google Maps web page.
Future<NavigationResult> openNavigation(double lat, double lon, String label, {required UriLauncher launcher}) async {
  if (await _try(launcher, googleNavigationUri(lat, lon))) return NavigationResult.googleNavigation;
  if (await _try(launcher, geoUri(lat, lon, label))) return NavigationResult.mapChooser;
  if (await _try(launcher, webDirectionsUri(lat, lon))) return NavigationResult.webPage;
  return NavigationResult.failed;
}

/// Opens the point in a map app the user chooses.
Future<bool> openInMapApp(double lat, double lon, String label, {required UriLauncher launcher}) =>
    _try(launcher, geoUri(lat, lon, label));

Future<bool> _try(UriLauncher launcher, Uri uri) async {
  try {
    return await launcher.launch(uri);
  } on Object {
    return false;
  }
}
