import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The basic primary colors the background can be.
enum ThemeColor {
  blue('Blue'),
  red('Red'),
  yellow('Yellow');

  const ThemeColor(this.label);
  final String label;
}

/// The colors the app's own widgets use (the backdrop, glass panels, the
/// accent for selected things). One per color and brightness; read it with
/// `context.pal`, so a screen never hard-codes a color.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.backdrop,
    required this.blobs,
    required this.accent,
    required this.ink,
    required this.glassTop,
    required this.glassBottom,
    required this.glassBorder,
  });

  /// The background gradient, top to bottom (4 colors).
  final List<Color> backdrop;

  /// Soft colored circles over the gradient (3 colors).
  final List<Color> blobs;

  /// Selected items and buttons.
  final Color accent;

  /// Normal text and icons.
  final Color ink;

  final Color glassTop, glassBottom, glassBorder;

  /// Text and icons on top of [accent].
  Color get onAccent {
    // White when it's readable (the usual look), black on light accents like yellow.
    final l = accent.computeLuminance() + 0.05;
    return 1.05 / l >= 4.0 ? Colors.white : Colors.black;
  }
  Color get muted => ink.withValues(alpha: .70);
  Color get field => ink.withValues(alpha: .10);
  Color get divider => ink.withValues(alpha: .14);

  static const backdropStops = [0.0, .42, .72, 1.0];

  static const _lightInk = Color(0xFF1A1C22);
  static const _darkInk = Colors.white;

  static AppPalette of(ThemeColor color, Brightness b) {
    final dark = b == Brightness.dark;
    final glass = dark
        ? (top: const Color(0x38FFFFFF), bottom: const Color(0x12FFFFFF), border: const Color(0x4DFFFFFF))
        : (top: const Color(0xB3FFFFFF), bottom: const Color(0x66FFFFFF), border: const Color(0xCCFFFFFF));
    final ink = dark ? _darkInk : _lightInk;
    AppPalette make(List<Color> backdrop, List<Color> blobs, Color accent) => AppPalette(
          backdrop: backdrop,
          blobs: blobs,
          accent: accent,
          ink: ink,
          glassTop: glass.top,
          glassBottom: glass.bottom,
          glassBorder: glass.border,
        );
    switch ((color, dark)) {
      case (ThemeColor.blue, true):
        return make(
          const [Color(0xFF1D44A8), Color(0xFF16337F), Color(0xFF0C1C4A), Color(0xFF060D26)],
          const [Color(0x884D8DFF), Color(0x663D6BFF), Color(0x5586B8FF)],
          const Color(0xFF5C94FF),
        );
      case (ThemeColor.blue, false):
        return make(
          const [Color(0xFFEAF1FF), Color(0xFFCFE0FF), Color(0xFFB5CEFF), Color(0xFFA3C0FF)],
          const [Color(0x884D8DFF), Color(0x555B9BFF), Color(0x55A0C4FF)],
          const Color(0xFF1A5FE0),
        );
      case (ThemeColor.red, true):
        return make(
          const [Color(0xFFA61F1F), Color(0xFF7A1616), Color(0xFF420B0B), Color(0xFF1C0404)],
          const [Color(0x88FF6B6B), Color(0x66FF3B3B), Color(0x55FF9A8A)],
          const Color(0xFFFF4D4D),
        );
      case (ThemeColor.red, false):
        return make(
          const [Color(0xFFFFEDEB), Color(0xFFFFD2CD), Color(0xFFFFB8B0), Color(0xFFFFA196)],
          const [Color(0x88FF6B6B), Color(0x55FF4D4D), Color(0x55FFB0A0)],
          const Color(0xFFD92B2B),
        );
      case (ThemeColor.yellow, true):
        return make(
          const [Color(0xFF5F4A00), Color(0xFF4E3F00), Color(0xFF382C00), Color(0xFF1A1400)],
          const [Color(0x88FFE15C), Color(0x66FFC700), Color(0x55FFF0A0)],
          const Color(0xFFFFD21F),
        );
      case (ThemeColor.yellow, false):
        return make(
          const [Color(0xFFFFFAD6), Color(0xFFFFF0A0), Color(0xFFFFE566), Color(0xFFFFDA3D)],
          const [Color(0x88FFD21F), Color(0x55FFC107), Color(0x55FFE98A)],
          const Color(0xFFF2B400),
        );
    }
  }

  @override
  AppPalette copyWith({
    List<Color>? backdrop,
    List<Color>? blobs,
    Color? accent,
    Color? ink,
    Color? glassTop,
    Color? glassBottom,
    Color? glassBorder,
  }) =>
      AppPalette(
        backdrop: backdrop ?? this.backdrop,
        blobs: blobs ?? this.blobs,
        accent: accent ?? this.accent,
        ink: ink ?? this.ink,
        glassTop: glassTop ?? this.glassTop,
        glassBottom: glassBottom ?? this.glassBottom,
        glassBorder: glassBorder ?? this.glassBorder,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    List<Color> mix(List<Color> a, List<Color> b) =>
        [for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t)!];
    return AppPalette(
      backdrop: mix(backdrop, other.backdrop),
      blobs: mix(blobs, other.blobs),
      accent: Color.lerp(accent, other.accent, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      glassTop: Color.lerp(glassTop, other.glassTop, t)!,
      glassBottom: Color.lerp(glassBottom, other.glassBottom, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
    );
  }
}

extension PaletteContext on BuildContext {
  AppPalette get pal => Theme.of(this).extension<AppPalette>()!;
}

/// The chosen light/dark mode and background color; remembered between runs.
class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.dark;
  ThemeColor color = ThemeColor.blue;
  SharedPreferences? _p;

  Future<void> load() async {
    try {
      _p = await SharedPreferences.getInstance();
      mode = ThemeMode.values.asNameMap()[_p!.getString('themeMode')] ?? mode;
      color = ThemeColor.values.asNameMap()[_p!.getString('themeColor')] ?? color;
    } catch (_) {
      // No saved choice: keep the defaults.
    }
  }

  void setMode(ThemeMode m) {
    if (m == mode) return;
    mode = m;
    _p?.setString('themeMode', m.name);
    notifyListeners();
  }

  void setColor(ThemeColor c) {
    if (c == color) return;
    color = c;
    _p?.setString('themeColor', c.name);
    notifyListeners();
  }

  ThemeData themeFor(Brightness b) {
    final pal = AppPalette.of(color, b);
    final scheme = ColorScheme.fromSeed(seedColor: pal.accent, brightness: b)
        .copyWith(primary: pal.accent, onPrimary: pal.onAccent);
    return ThemeData(
      brightness: b,
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent,
      extensions: [pal],
      chipTheme: ChipThemeData(
        selectedColor: pal.accent,
        checkmarkColor: pal.onAccent,
        secondaryLabelStyle: TextStyle(color: pal.onAccent),
      ),
      // Same hue as the background, so plain buttons use the text color, not the accent.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: pal.ink,
          side: BorderSide(color: pal.ink.withValues(alpha: .45)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: pal.ink)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? pal.accent : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? pal.onAccent : pal.ink),
          side: WidgetStatePropertyAll(BorderSide(color: pal.ink.withValues(alpha: .35))),
        ),
      ),
    );
  }
}
