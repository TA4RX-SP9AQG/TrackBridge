import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Section title with an optional subtitle and trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xs, Gaps.xl, Gaps.xs, Gaps.s),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(title, style: theme.textTheme.titleMedium)),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// The app's standard card: soft border, no shadow, optional tap target.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(Gaps.l), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(child: onTap == null ? content : InkWell(onTap: onTap, child: content));
  }
}

enum PillTone { neutral, success, warning, accent, error }

/// Small rounded label with an optional icon. Never relies on colour alone: it always carries text.
class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.icon, this.tone = PillTone.neutral});

  final String text;
  final IconData? icon;
  final PillTone tone;

  (Color, Color) _colors(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return switch (tone) {
      PillTone.neutral => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
      PillTone.success => dark ? (const Color(0xFF14382A), const Color(0xFF8FE0AE)) : (const Color(0xFFDDF5E4), const Color(0xFF0F5A2A)),
      PillTone.warning => dark ? (const Color(0xFF3F3210), const Color(0xFFF2D16B)) : (const Color(0xFFFFF0C2), const Color(0xFF5A4300)),
      PillTone.accent => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      PillTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.m, vertical: Gaps.xs + 1),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.xl)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          ExcludeSemantics(child: Icon(icon, size: 16, color: foreground)),
          const SizedBox(width: Gaps.xs + 2),
        ],
        Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground)),
      ]),
    );
  }
}

/// Centered explanation shown when a list has nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
            child: ExcludeSemantics(child: Icon(icon, size: 34, color: scheme.onPrimaryContainer)),
          ),
          const SizedBox(height: Gaps.l),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: Gaps.s),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: Gaps.l), action!],
        ]),
      ),
    );
  }
}

/// Round badge with the first two characters of a callsign. The colour is stable per name.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 44});

  final String name;
  final double size;

  static String initials(String name) {
    final letters = name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (letters.isEmpty) return '?';
    return letters.length == 1 ? letters : letters.substring(0, 2);
  }

  static int variant(String name) => name.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff) % 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (variant(name)) {
      0 => (scheme.primaryContainer, scheme.onPrimaryContainer),
      1 => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Text(
          initials(name),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: foreground, fontSize: size * 0.34),
        ),
      ),
    );
  }
}

/// Big status card on the brand gradient (white text, at least 4.8:1 on every stop).
class BrandHeroCard extends StatelessWidget {
  const BrandHeroCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.footer,
    this.muted = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? footer;

  /// Neutral surface instead of the brand gradient (for "not connected" states).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = muted ? scheme.onSurface : Colors.white;
    final secondary = muted ? scheme.onSurfaceVariant : Colors.white.withValues(alpha: 0.92);
    return Container(
      padding: const EdgeInsets.all(Gaps.l + 2),
      decoration: BoxDecoration(
        gradient: muted ? null : BrandColors.gradient,
        color: muted ? scheme.surfaceContainerHigh : null,
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: muted ? scheme.surfaceContainerHighest : Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: ExcludeSemantics(child: Icon(icon, color: foreground, size: 28)),
          ),
          const SizedBox(width: Gaps.l),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(color: foreground)),
              if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: secondary)),
            ]),
          ),
          ?trailing,
        ]),
        if (footer != null) ...[const SizedBox(height: Gaps.l), footer!],
      ]),
    );
  }
}

/// Pill-shaped chip used on the hero card (translucent white, readable on the gradient).
class HeroChip extends StatelessWidget {
  const HeroChip(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.m, vertical: Gaps.xs + 1),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(Radii.xl)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          ExcludeSemantics(child: Icon(icon, size: 15, color: Colors.white)),
          const SizedBox(width: Gaps.xs + 2),
        ],
        Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white)),
      ]),
    );
  }
}
