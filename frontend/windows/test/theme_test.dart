import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nme/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// WCAG contrast ratio between two opaque colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('every color and mode keeps text readable', () {
    final problems = <String>[];
    void check(String what, double got, double need) {
      if (got < need) problems.add('$what: ${got.toStringAsFixed(2)} < $need');
    }

    for (final color in ThemeColor.values) {
      for (final b in Brightness.values) {
        final pal = AppPalette.of(color, b);
        final name = '${color.name} ${b.name}';
        // Buttons and selected items: text on the accent.
        check('$name accent text', contrast(pal.accent, pal.onAccent), 3.0);
        // Text sits on glass over the backdrop: check each gradient stop with the glass tint on top.
        for (var i = 0; i < pal.backdrop.length; i++) {
          final stop = pal.backdrop[i];
          check('$name text on glass over stop $i (bottom)',
              contrast(Color.alphaBlend(pal.glassBottom, stop), pal.ink), 4.5);
          check('$name text on glass over stop $i (top)',
              contrast(Color.alphaBlend(pal.glassTop, stop), pal.ink), 4.5);
        }
        // The selected nav pill must stand out from the glass behind it.
        final glass = Color.alphaBlend(pal.glassTop, pal.backdrop[1]);
        check('$name accent vs glass', contrast(glass, pal.accent), 1.5);
      }
    }
    expect(problems, isEmpty, reason: problems.join(', '));
  });

  test('light and dark are really different', () {
    for (final color in ThemeColor.values) {
      final light = AppPalette.of(color, Brightness.light).backdrop.first.computeLuminance();
      final dark = AppPalette.of(color, Brightness.dark).backdrop.last.computeLuminance();
      expect(light, greaterThan(dark + 0.3), reason: color.name);
    }
  });

  test('the choice is remembered between runs', () async {
    SharedPreferences.setMockInitialValues({});
    final a = ThemeController();
    await a.load();
    expect(a.mode, ThemeMode.dark);
    expect(a.color, ThemeColor.blue);

    var changes = 0;
    a.addListener(() => changes++);
    a.setMode(ThemeMode.light);
    a.setColor(ThemeColor.yellow);
    a.setColor(ThemeColor.yellow); // same again: no change
    expect(changes, 2);

    final b = ThemeController(); // "next launch"
    await b.load();
    expect(b.mode, ThemeMode.light);
    expect(b.color, ThemeColor.yellow);
  });

  test('a damaged saved value falls back to the default', () async {
    SharedPreferences.setMockInitialValues({'themeMode': 'purple', 'themeColor': 'green'});
    final c = ThemeController();
    await c.load();
    expect(c.mode, ThemeMode.dark);
    expect(c.color, ThemeColor.blue);
  });

  test('the theme carries the palette and the right brightness', () {
    final c = ThemeController()..color = ThemeColor.red;
    final dark = c.themeFor(Brightness.dark);
    final light = c.themeFor(Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(dark.extension<AppPalette>()!.accent, AppPalette.of(ThemeColor.red, Brightness.dark).accent);
    expect(dark.colorScheme.primary, dark.extension<AppPalette>()!.accent);
    expect(light.colorScheme.onPrimary, light.extension<AppPalette>()!.onAccent);
  });
}
