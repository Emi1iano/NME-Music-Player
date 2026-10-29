import 'package:flutter/material.dart';

import 'services/appearance.dart';

// All the app's colors in one place, so the look can be changed by editing
// this file only. (0xFF = fully opaque, then the usual RRGGBB hex color.)
class AppColors {
  // The background is picked in Settings → Appearance; cards ("surface"),
  // raised parts ("surfaceHigh") and lines are the same color, a little
  // lighter. In Glass style, cards and raised parts are see-through.
  static Color get background => Appearance.instance.background;
  static Color get surface => _glassy(_lighter(0.05), 0.70);
  static Color get surfaceHigh => _glassy(_lighter(0.10), 0.72);
  // Sheets and dialogs sit on top of other content, so they stay nearly solid.
  static Color get sheet => _glassy(_lighter(0.05), 0.92);
  // The accent is picked in Settings → Appearance, so it isn't a constant.
  static Color get accent => Appearance.instance.accent;
  // Text/icons drawn ON the accent: white or near-black, whichever reads better.
  static Color get onAccent => _readableOn(accent);
  static const textPrimary = Color(0xFFF2F2F5);
  static const textSecondary = Color(0xFF9A9AA5);
  static Color get divider => _lighter(0.12);

  static Color _lighter(double amount) => Color.lerp(background, Colors.white, amount)!;
  static Color _glassy(Color c, double alpha) =>
      Appearance.instance.glass ? c.withValues(alpha: alpha) : c;

  static Color _readableOn(Color c) {
    final l = c.computeLuminance();
    final onWhite = 1.05 / (l + 0.05);
    final onDark = (l + 0.05) / (background.computeLuminance() + 0.05);
    return onWhite >= onDark ? Colors.white : background;
  }
}

// Builds the dark Material 3 theme used by MaterialApp in main.dart.
// Setting styles here (nav bar, slider, sheets...) means individual screens
// don't have to style each widget themselves.
ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.background,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outlineVariant: AppColors.divider,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.accent.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.textSecondary,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.textSecondary,
          )),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: AppColors.textPrimary,
      inactiveTrackColor: AppColors.surfaceHigh,
      thumbColor: AppColors.textPrimary,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.sheet,
      shape: Appearance.instance.glass
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(36)))
          : null,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.sheet,
      shape: Appearance.instance.glass
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(36))
          : null,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
