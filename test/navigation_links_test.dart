import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/core/navigation_links.dart';

import 'helpers/fakes.dart';

void main() {
  group('link builders', () {
    test('Google Maps navigation intent uses six decimals', () {
      expect(googleNavigationUri(52.229667, 21.012167).toString(), 'google.navigation:q=52.229667,21.012167&mode=d');
      expect(googleNavigationUri(-33.5, -70.25).toString(), 'google.navigation:q=-33.500000,-70.250000&mode=d');
    });

    test('geo uri carries a percent-encoded label', () {
      expect(geoUri(52.5, 21.0, 'N1TEST-7 (walk)').toString(), 'geo:0,0?q=52.500000,21.000000(N1TEST-7%20(walk))');
    });

    test('web directions fallback', () {
      final uri = webDirectionsUri(52.5, 21.0);
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['destination'], '52.500000,21.000000');
      expect(uri.queryParameters['api'], '1');
    });
  });

  group('openNavigation', () {
    test('uses Google Maps navigation first', () async {
      final l = FakeLauncher(accepts: {'google.navigation', 'geo', 'https'});
      final result = await openNavigation(52.5, 21.0, 'X', launcher: l);
      expect(result, NavigationResult.googleNavigation);
      expect(l.tried, hasLength(1));
    });

    test('falls back to the geo chooser, then to the web page', () async {
      var l = FakeLauncher(accepts: {'geo', 'https'});
      expect(await openNavigation(52.5, 21.0, 'X', launcher: l), NavigationResult.mapChooser);
      expect(l.tried.map((u) => u.scheme), ['google.navigation', 'geo']);

      l = FakeLauncher(accepts: {'https'});
      expect(await openNavigation(52.5, 21.0, 'X', launcher: l), NavigationResult.webPage);
      expect(l.tried.map((u) => u.scheme), ['google.navigation', 'geo', 'https']);
    });

    test('reports failure when nothing can open it, and survives launcher exceptions', () async {
      final l = FakeLauncher(throwFor: {'google.navigation', 'geo', 'https'});
      expect(await openNavigation(52.5, 21.0, 'X', launcher: l), NavigationResult.failed);
      expect(l.tried, hasLength(3));
    });

    test('openInMapApp goes straight to the chooser', () async {
      final l = FakeLauncher(accepts: {'geo'});
      expect(await openInMapApp(52.5, 21.0, 'X', launcher: l), isTrue);
      expect(l.tried.single.scheme, 'geo');
    });
  });
}
