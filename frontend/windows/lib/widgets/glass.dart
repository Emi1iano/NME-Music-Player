import 'dart:ui';
import 'package:flutter/material.dart';

/// A frosted-glass panel: blurs whatever's behind it, then lays a
/// translucent tint + soft light border on top. This is the building
/// block for the iOS-style "glass" look — every surface (sidebar,
/// transport bar, cards) should be built from this instead of a flat
/// opaque Container.
class Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final Color tint;
  final double tintOpacity;
  final Color borderColor;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadows;

  const Glass({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blur = 24,
    this.tint = Colors.white,
    this.tintOpacity = 0.06,
    this.borderColor = const Color(0x33FFFFFF),
    this.padding,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: tint.withOpacity(tintOpacity),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: shadows,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.10),
                Colors.white.withOpacity(0.02),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Soft, blurred color blobs placed behind the glass UI so there's
/// actually something colorful for the frosted panels to refract.
/// Without this, glass panels over a flat background just look like
/// dim gray boxes.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF0B0B10)),
        Positioned(
          top: -120,
          left: -80,
          child: _Blob(size: 420, color: const Color(0xFFC08A4E).withOpacity(0.35)),
        ),
        Positioned(
          top: 120,
          right: -140,
          child: _Blob(size: 380, color: const Color(0xFF4E7FC0).withOpacity(0.28)),
        ),
        Positioned(
          bottom: -160,
          left: 60,
          child: _Blob(size: 460, color: const Color(0xFF9CB86B).withOpacity(0.22)),
        ),
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ).let((w) => ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90), child: w));
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
