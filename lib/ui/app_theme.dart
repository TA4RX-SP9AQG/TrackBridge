import 'package:flutter/material.dart';

/// Brand colours, taken from the app icon: an indigo-to-blue background and an orange pin.
class BrandColors {
  const BrandColors._();

  static const Color indigo = Color(0xFF4338CA);
  static const Color blue = Color(0xFF2A62C8);
  static const Color sky = Color(0xFF2F6BE0);

  /// Background of hero surfaces. White text on every stop is at least 4.8:1.
  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, blue, sky],
  );
}

/// 4/8 dp spacing rhythm.
class Gaps {
  const Gaps._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
class Radii {
  const Radii._();

  static const double s = 10;
  static const double m = 14;
  static const double l = 20;
  static const double xl = 28;
}

/// Style for buttons that put a packet on the air. Orange, so transmitting is
/// always visually distinct from navigating or saving.
ButtonStyle transmitButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(backgroundColor: scheme.tertiary, foregroundColor: scheme.onTertiary);
}

/// App-wide themes (Material 3, hand-tuned light and dark palettes).
///
/// Every text/background pair used by the palettes has a contrast ratio of at
/// least 4.5:1 and every outline against its card at least 3:1, in both modes.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF2A56C8);

  static final ColorScheme _lightScheme = ColorScheme.fromSeed(seedColor: _seed).copyWith(
    primary: const Color(0xFF2A56C8),
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFDCE5FF),
    onPrimaryContainer: const Color(0xFF0A2064),
    secondary: const Color(0xFF565E8F),
    secondaryContainer: const Color(0xFFE0E3FF),
    onSecondaryContainer: const Color(0xFF131B4B),
    tertiary: const Color(0xFFB84E00),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFFFDDC6),
    onTertiaryContainer: const Color(0xFF4F1F00),
    surface: const Color(0xFFF4F6FB),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF8F9FD),
    surfaceContainer: const Color(0xFFEEF1F8),
    surfaceContainerHigh: const Color(0xFFE8ECF5),
    surfaceContainerHighest: const Color(0xFFE2E7F2),
    onSurface: const Color(0xFF171B26),
    onSurfaceVariant: const Color(0xFF454C60),
    outline: const Color(0xFF6F768C),
    outlineVariant: const Color(0xFFCBD1E1),
  );

  static final ColorScheme _darkScheme = ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark).copyWith(
    primary: const Color(0xFFB4C6FF),
    onPrimary: const Color(0xFF06267A),
    primaryContainer: const Color(0xFF1F3EA0),
    onPrimaryContainer: const Color(0xFFDCE5FF),
    secondary: const Color(0xFFBCC3F7),
    secondaryContainer: const Color(0xFF2B3363),
    onSecondaryContainer: const Color(0xFFE0E3FF),
    tertiary: const Color(0xFFFFB784),
    onTertiary: const Color(0xFF4A1C00),
    tertiaryContainer: const Color(0xFF7A3500),
    onTertiaryContainer: const Color(0xFFFFDDC6),
    surface: const Color(0xFF0E1220),
    surfaceContainerLowest: const Color(0xFF0A0D18),
    surfaceContainerLow: const Color(0xFF131829),
    surfaceContainer: const Color(0xFF171C2E),
    surfaceContainerHigh: const Color(0xFF1E2438),
    surfaceContainerHighest: const Color(0xFF272E46),
    onSurface: const Color(0xFFE3E6F3),
    onSurfaceVariant: const Color(0xFFB7BDD2),
    outline: const Color(0xFF8790AB),
    outlineVariant: const Color(0xFF2E3650),
  );

  static ThemeData light() => _build(_lightScheme);

  static ThemeData dark() => _build(_darkScheme);

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(brightness: scheme.brightness, useMaterial3: true).textTheme;
    final textTheme = base
        .copyWith(
          headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final cardColor = scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainer;
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.l),
      side: BorderSide(color: scheme.outlineVariant),
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m));
    const buttonPadding = EdgeInsets.symmetric(horizontal: Gaps.xl, vertical: Gaps.m);
    const buttonSize = Size(64, 52);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => textTheme.labelMedium?.copyWith(
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 24,
              color: states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            )),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          side: BorderSide(color: scheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.brightness == Brightness.light ? scheme.surfaceContainerLow : scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.m + 2),
        border: inputBorder(scheme.outlineVariant),
        enabledBorder: inputBorder(scheme.outlineVariant),
        focusedBorder: inputBorder(scheme.primary, 2),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 2),
        helperStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.s)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: Colors.transparent,
        selectedColor: scheme.primaryContainer,
        labelStyle: textTheme.labelLarge,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
          side: BorderSide(color: scheme.outline),
          minimumSize: const Size(48, 48),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.brightness == Brightness.light ? scheme.surfaceContainerLowest : scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.l, vertical: Gaps.xs),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.m)),
        iconColor: scheme.onSurfaceVariant,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        inactiveTrackColor: scheme.outlineVariant,
      ),
    );
  }
}
