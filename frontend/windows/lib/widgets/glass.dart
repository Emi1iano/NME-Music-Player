import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets pad;
  const Glass({super.key, required this.child, this.radius = 28, this.pad = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext c) {
    final r = BorderRadius.circular(radius);
    final pal = c.pal;
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: pal.glassBorder, width: 1.2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [pal.glassTop, pal.glassBottom],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The colored background behind everything; follows the chosen color and mode.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key});
  Widget blob(Color col, double s) =>
      Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: col));
  @override
  Widget build(BuildContext c) {
    final pal = c.pal;
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: pal.backdrop,
            stops: AppPalette.backdropStops,
          ),
        ),
      ),
      Positioned(left: -80, top: 60, child: blob(pal.blobs[0], 320)),
      Positioned(right: -60, top: 240, child: blob(pal.blobs[1], 280)),
      Positioned(left: 200, bottom: -120, child: blob(pal.blobs[2], 340)),
      BackdropFilter(filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50), child: const SizedBox.expand()),
    ]);
  }
}
