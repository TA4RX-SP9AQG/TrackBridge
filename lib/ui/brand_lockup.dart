import 'package:flutter/material.dart';

/// The TrackBridge logo with its name, picking the variant that is legible on
/// the current theme (the "dark" file has light lettering for dark backgrounds).
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      child: Image.asset(
        dark ? 'assets/branding/lockup-stacked-dark.png' : 'assets/branding/lockup-stacked-light.png',
        fit: BoxFit.contain,
        semanticLabel: 'TrackBridge',
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
