import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color + type tokens, ported 1:1 from the HTML prototype's CSS variables.
class AppColors {
  static const bgBase = Color(0xFF121212);
  static const bgPanel = Color(0xFF191919);
  static const bgElevated = Color(0xFF212121);
  static const bgSunken = Color(0xFF0D0D0D);
  static const hairline = Color(0xFF2E2C29);
  static const hairlineSoft = Color(0xFF232220);
  static const textPrimary = Color(0xFFEDEAE3);
  static const textSecondary = Color(0xFF8C877D);
  static const textTertiary = Color(0xFF5C584F);
  static const accent = Color(0xFFC08A4E);
  static const accentDim = Color(0xFF8A6438);
  static const vu = Color(0xFF9CB86B);
}

class AppText {
  // Space Grotesk for UI text, IBM Plex Mono for numeric/status readouts
  // (durations, sync stats) - mirrors the "hardware LCD readout" idea from
  // the mockup. Keep mono usage limited to numbers/status, not body text.
  static TextStyle ui({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textPrimary,
  }) =>
      GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight, color: color);

  static TextStyle mono({
    double size = 11.5,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.textSecondary,
  }) =>
      GoogleFonts.ibmPlexMono(fontSize: size, fontWeight: weight, color: color);
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bgBase,
    fontFamily: GoogleFonts.spaceGrotesk().fontFamily,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.bgPanel,
    ),
    dividerColor: AppColors.hairlineSoft,
  );
}
