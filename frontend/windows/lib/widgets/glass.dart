import 'dart:ui';
import 'package:flutter/material.dart';

class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets pad;
  const Glass({super.key, required this.child, this.radius = 28, this.pad = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext c) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            borderRadius: r,
            border: Border.all(color: Colors.white.withOpacity(.30), width: 1.2),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withOpacity(.22), Colors.white.withOpacity(.07)],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class Backdrop extends StatelessWidget {
  const Backdrop({super.key});
  Widget blob(Color col, double s) =>
      Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: col));
  @override
  Widget build(BuildContext c) => Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF2B27A), Color(0xFFE08A5B), Color(0xFF3B4A3A), Color(0xFF1C2A1F)],
              stops: [0, .42, .72, 1],
            ),
          ),
        ),
        Positioned(left: -80, top: 60, child: blob(const Color(0x88FFD9A0), 320)),
        Positioned(right: -60, top: 240, child: blob(const Color(0x66E8622A), 280)),
        Positioned(left: 200, bottom: -120, child: blob(const Color(0x5590B070), 340)),
        BackdropFilter(filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50), child: const SizedBox.expand()),
      ]);
}
