import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/ui/brand_lockup.dart';

Future<String> assetShown(WidgetTester tester, Brightness brightness) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: const Scaffold(body: BrandLockup(height: 100)),
  ));
  final image = tester.widget<Image>(find.byType(Image));
  return (image.image as AssetImage).assetName;
}

void main() {
  testWidgets('uses the dark-background lockup in dark theme', (tester) async {
    expect(await assetShown(tester, Brightness.dark), 'assets/branding/lockup-stacked-dark.png');
  });

  testWidgets('uses the light-background lockup in light theme', (tester) async {
    expect(await assetShown(tester, Brightness.light), 'assets/branding/lockup-stacked-light.png');
  });

  testWidgets('is labelled for screen readers and keeps the requested height', (tester) async {
    await assetShown(tester, Brightness.light);
    expect(find.bySemanticsLabel('TrackBridge'), findsOneWidget);
    expect(tester.getSize(find.byType(BrandLockup)).height, 100);
  });
}
