import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

/// Pick light or dark mode and the background color (the basic primary colors).
class AppearanceScreen extends StatelessWidget {
  final ThemeController theme;
  const AppearanceScreen(this.theme, {super.key});

  @override
  Widget build(BuildContext c) {
    final brightness = Theme.of(c).brightness;
    return Glass(
      child: ListView(children: [
        Text('Appearance', style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 20),
        const Text('Mode', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Dark')),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('System')),
          ],
          selected: {theme.mode},
          onSelectionChanged: (m) => theme.setMode(m.first),
        ),
        const SizedBox(height: 6),
        Text('System follows your Windows light or dark setting.',
            style: TextStyle(fontSize: 12, color: c.pal.muted)),
        const SizedBox(height: 28),
        const Text('Background color', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 16, children: [
          for (final color in ThemeColor.values)
            _Swatch(
              color: color,
              brightness: brightness,
              selected: theme.color == color,
              onTap: () => theme.setColor(color),
            ),
        ]),
      ]),
    );
  }
}

/// One choice: a small preview of that color's background.
class _Swatch extends StatelessWidget {
  final ThemeColor color;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({required this.color, required this.brightness, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final preview = AppPalette.of(color, brightness);
    return Semantics(
      button: true,
      selected: selected,
      label: '${color.label} background',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: SizedBox(
          width: 112,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 112,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? c.pal.ink : c.pal.divider, width: selected ? 3 : 1),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: preview.backdrop,
                  stops: AppPalette.backdropStops,
                ),
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: preview.accent,
                    child: selected ? Icon(Icons.check_rounded, size: 15, color: preview.onAccent) : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(color.label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}
