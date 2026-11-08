import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackbridge/ui/app_theme.dart';
import 'package:trackbridge/ui/widgets/ui_kit.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(body: child),
    );

double luminance(Color c) => c.computeLuminance();

double contrast(Color a, Color b) {
  final la = luminance(a);
  final lb = luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('palette contrast (WCAG)', () {
    for (final b in [Brightness.light, Brightness.dark]) {
      final scheme = (b == Brightness.light ? AppTheme.light() : AppTheme.dark()).colorScheme;
      test('${b.name}: text pairs are at least 4.5:1', () {
        final pairs = <String, (Color, Color)>{
          'onSurface/surface': (scheme.onSurface, scheme.surface),
          'onSurfaceVariant/surface': (scheme.onSurfaceVariant, scheme.surface),
          'onSurfaceVariant/card': (scheme.onSurfaceVariant, scheme.surfaceContainerLowest),
          'onPrimary/primary': (scheme.onPrimary, scheme.primary),
          'onPrimaryContainer/primaryContainer': (scheme.onPrimaryContainer, scheme.primaryContainer),
          'onSecondaryContainer/secondaryContainer': (scheme.onSecondaryContainer, scheme.secondaryContainer),
          'onTertiary/tertiary (transmit button)': (scheme.onTertiary, scheme.tertiary),
          'onTertiaryContainer/tertiaryContainer': (scheme.onTertiaryContainer, scheme.tertiaryContainer),
          'onError/error': (scheme.onError, scheme.error),
          'primary/surface (links)': (scheme.primary, scheme.surface),
        };
        for (final e in pairs.entries) {
          expect(contrast(e.value.$1, e.value.$2), greaterThanOrEqualTo(4.5), reason: e.key);
        }
      });

      test('${b.name}: outlines and dividers are visible (>= 1.3 for hairlines, >= 3 for control outlines)', () {
        final card = b == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainer;
        expect(contrast(scheme.outline, card), greaterThanOrEqualTo(3));
        expect(contrast(scheme.outlineVariant, card), greaterThanOrEqualTo(1.3));
      });
    }

    test('white text on every stop of the brand gradient is at least 4.5:1', () {
      for (final c in BrandColors.gradient.colors) {
        expect(contrast(Colors.white, c), greaterThanOrEqualTo(4.5), reason: '$c');
      }
    });
  });

  group('components', () {
    testWidgets('SectionHeader exposes a semantic header and shows the subtitle', (tester) async {
      await tester.pumpWidget(host(const SectionHeader('Duyulan paketler', subtitle: '5 paket')));
      expect(find.text('Duyulan paketler'), findsOneWidget);
      expect(find.text('5 paket'), findsOneWidget);
      expect(tester.getSemantics(find.text('Duyulan paketler')).flagsCollection.isHeader, isTrue);
    });

    testWidgets('StatusPill always carries text, in every tone and theme', (tester) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        for (final tone in PillTone.values) {
          await tester.pumpWidget(host(StatusPill('Etiket', icon: Icons.check, tone: tone), brightness: b));
          expect(find.text('Etiket'), findsOneWidget, reason: '${b.name}/${tone.name}');
        }
      }
    });

    testWidgets('EmptyState shows title, message and optional action', (tester) async {
      await tester.pumpWidget(host(EmptyState(
        icon: Icons.chat,
        title: 'Başlık',
        message: 'Açıklama',
        action: FilledButton(onPressed: () {}, child: const Text('Aksiyon')),
      )));
      expect(find.text('Başlık'), findsOneWidget);
      expect(find.text('Açıklama'), findsOneWidget);
      expect(find.text('Aksiyon'), findsOneWidget);
    });

    test('InitialsAvatar: initials and a stable colour variant per name', () {
      expect(InitialsAvatar.initials('N1TEST-7'), 'N1');
      expect(InitialsAvatar.initials('a'), 'A');
      expect(InitialsAvatar.initials('--'), '?');
      expect(InitialsAvatar.variant('SP9AQG-9'), InitialsAvatar.variant('SP9AQG-9'));
      expect({for (final n in ['N1TEST-7', 'SP9AQG', 'TA4RX', 'W1AW', 'DL1ABC', 'F4XYZ']) InitialsAvatar.variant(n)},
          everyElement(inInclusiveRange(0, 2)));
    });

    testWidgets('SurfaceCard is tappable only when given a callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(SurfaceCard(onTap: () => taps++, child: const Text('x'))));
      await tester.tap(find.text('x'));
      expect(taps, 1);
      await tester.pumpWidget(host(const SurfaceCard(child: Text('y'))));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('BrandHeroCard renders title, subtitle and footer', (tester) async {
      await tester.pumpWidget(host(const BrandHeroCard(
        icon: Icons.bluetooth_connected,
        title: 'Bağlı',
        subtitle: 'LoRaTracker',
        footer: HeroChip('MTU 247', icon: Icons.speed),
      )));
      expect(find.text('Bağlı'), findsOneWidget);
      expect(find.text('LoRaTracker'), findsOneWidget);
      expect(find.text('MTU 247'), findsOneWidget);
    });
  });

  group('transmit button style', () {
    testWidgets('uses the accent colour pair', (tester) async {
      late ButtonStyle style;
      late ColorScheme scheme;
      await tester.pumpWidget(host(Builder(builder: (context) {
        style = transmitButtonStyle(context);
        scheme = Theme.of(context).colorScheme;
        return const SizedBox();
      })));
      expect(style.backgroundColor?.resolve({}), scheme.tertiary);
      expect(style.foregroundColor?.resolve({}), scheme.onTertiary);
    });
  });
}
