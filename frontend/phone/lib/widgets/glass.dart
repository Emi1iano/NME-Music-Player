import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/appearance.dart';
import '../theme.dart';

// Glass style (Settings → Appearance → Glass style): a soft glow of the
// accent color behind a screen, with frosted, see-through cards and bars on
// top of it. Everything here does nothing when Glass style is off.

/// Puts the glow behind [child] when Glass style is on.
Widget withGlassGlow(Widget child) {
  if (!Appearance.instance.glass) return child;
  return Stack(children: [
    const Positioned.fill(child: GlassGlow()),
    child,
  ]);
}

/// The glow: the background color with two large, soft blobs of the accent
/// color (one shifted in hue) in opposite corners. Kept faint (15% at the
/// brightest) so grey text stays readable (4.5:1+) with every accent and
/// background.
class GlassGlow extends StatelessWidget {
  const GlassGlow({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accent;
    final hsl = HSLColor.fromColor(accent);
    final second = hsl.withHue((hsl.hue + 50) % 360).toColor();
    Widget blob(Alignment at, Color color, double alpha) => Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: at,
                radius: 1.1,
                colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    return ColoredBox(
      color: AppColors.background,
      child: Stack(children: [
        blob(const Alignment(-1.0, -0.9), accent, 0.15),
        blob(const Alignment(1.0, 0.7), second, 0.11),
      ]),
    );
  }
}

/// Blurs whatever is behind [child] (frosted glass) when Glass style is on.
/// [child] should have a see-through color, like AppColors.surface in Glass
/// style, so the blur shows.
class Frosted extends StatelessWidget {
  final Widget child;
  const Frosted({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!Appearance.instance.glass) return child;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: child,
      ),
    );
  }
}

/// A floating frosted shape (Glass style): blurs what's behind it, tints it
/// with the see-through surface color, and adds a thin light edge, like
/// Apple's glass. Used for the floating tab bar and mini player.
class GlassPill extends StatelessWidget {
  final Widget child;
  final double radius;
  const GlassPill({super.key, required this.child, this.radius = 28});

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: shape,
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}
