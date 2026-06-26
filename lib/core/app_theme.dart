import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Palette ─────────────────────────────────────────────────────────────
  static const Color sosRed       = Color(0xFFFF1919);
  static const Color rescueBlue   = Color(0xFF1A90FF);
  static const Color warningAmber = Color(0xFFFFB300);
  static const Color successGreen = Color(0xFF00C46A);
  static const Color infoCyan     = Color(0xFF00D4FF);

  // Dark surfaces
  static const Color _ink         = Color(0xFF0C0F1A);
  static const Color _surface     = Color(0xFF141B2D);
  static const Color _surfaceVar  = Color(0xFF1E2A40);
  static const Color _surfaceHigh = Color(0xFF243350);
  static const Color _border      = Color(0xFF2E3D5A);

  // Light surfaces
  static const Color _lBg         = Color(0xFFF2F4FA);
  static const Color _lSurface    = Color(0xFFFFFFFF);
  static const Color _lSurfaceVar = Color(0xFFEDF0F8);
  static const Color _lBorder     = Color(0xFFD0D8EF);

  // Text
  static const Color _dTextPrimary   = Color(0xFFE8ECF4);
  static const Color _dTextSecondary = Color(0xFF8A9BC2);
  static const Color _dTextHint      = Color(0xFF4A5A7A);

  static const Color _lTextPrimary   = Color(0xFF0C0F1A);
  static const Color _lTextSecondary = Color(0xFF4A5A7A);
  static const Color _lTextHint      = Color(0xFFA0AABF);

  // Public access for widgets
  static const Color inkBackground         = _ink;
  static const Color cardBackground        = _surface;
  static const Color cardBackgroundElevated = _surfaceVar;
  static const Color borderColor           = _border;
  static const Color textPrimary           = _dTextPrimary;
  static const Color textSecondary         = _dTextSecondary;
  static const Color textHint              = _dTextHint;

  // ── Typography ───────────────────────────────────────────────────────────
  static TextTheme _darkText() => TextTheme(
    displayLarge:  GoogleFonts.barlowCondensed(fontSize: 36, fontWeight: FontWeight.w700, color: _dTextPrimary, letterSpacing: 0.5),
    displayMedium: GoogleFonts.barlowCondensed(fontSize: 30, fontWeight: FontWeight.w700, color: _dTextPrimary),
    displaySmall:  GoogleFonts.barlowCondensed(fontSize: 26, fontWeight: FontWeight.w700, color: _dTextPrimary),
    headlineLarge: GoogleFonts.barlowCondensed(fontSize: 24, fontWeight: FontWeight.w700, color: _dTextPrimary, letterSpacing: 0.3),
    headlineMedium:GoogleFonts.barlowCondensed(fontSize: 20, fontWeight: FontWeight.w600, color: _dTextPrimary),
    headlineSmall: GoogleFonts.barlowCondensed(fontSize: 18, fontWeight: FontWeight.w600, color: _dTextPrimary),
    titleLarge:    GoogleFonts.barlow(fontSize: 18, fontWeight: FontWeight.w600, color: _dTextPrimary),
    titleMedium:   GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w500, color: _dTextPrimary),
    titleSmall:    GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w500, color: _dTextPrimary),
    bodyLarge:     GoogleFonts.barlow(fontSize: 16, color: _dTextPrimary),
    bodyMedium:    GoogleFonts.barlow(fontSize: 14, color: _dTextPrimary),
    bodySmall:     GoogleFonts.barlow(fontSize: 12, color: _dTextSecondary),
    labelLarge:    GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w600, color: _dTextPrimary, letterSpacing: 0.5),
    labelMedium:   GoogleFonts.barlow(fontSize: 12, fontWeight: FontWeight.w500, color: _dTextSecondary),
    labelSmall:    GoogleFonts.barlow(fontSize: 10, fontWeight: FontWeight.w500, color: _dTextHint, letterSpacing: 0.5),
  );

  static TextTheme _lightText() => TextTheme(
    displayLarge:  GoogleFonts.barlowCondensed(fontSize: 36, fontWeight: FontWeight.w700, color: _lTextPrimary, letterSpacing: 0.5),
    displayMedium: GoogleFonts.barlowCondensed(fontSize: 30, fontWeight: FontWeight.w700, color: _lTextPrimary),
    displaySmall:  GoogleFonts.barlowCondensed(fontSize: 26, fontWeight: FontWeight.w700, color: _lTextPrimary),
    headlineLarge: GoogleFonts.barlowCondensed(fontSize: 24, fontWeight: FontWeight.w700, color: _lTextPrimary),
    headlineMedium:GoogleFonts.barlowCondensed(fontSize: 20, fontWeight: FontWeight.w600, color: _lTextPrimary),
    headlineSmall: GoogleFonts.barlowCondensed(fontSize: 18, fontWeight: FontWeight.w600, color: _lTextPrimary),
    titleLarge:    GoogleFonts.barlow(fontSize: 18, fontWeight: FontWeight.w600, color: _lTextPrimary),
    titleMedium:   GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w500, color: _lTextPrimary),
    titleSmall:    GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w500, color: _lTextPrimary),
    bodyLarge:     GoogleFonts.barlow(fontSize: 16, color: _lTextPrimary),
    bodyMedium:    GoogleFonts.barlow(fontSize: 14, color: _lTextPrimary),
    bodySmall:     GoogleFonts.barlow(fontSize: 12, color: _lTextSecondary),
    labelLarge:    GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w600, color: _lTextPrimary),
    labelMedium:   GoogleFonts.barlow(fontSize: 12, fontWeight: FontWeight.w500, color: _lTextSecondary),
    labelSmall:    GoogleFonts.barlow(fontSize: 10, fontWeight: FontWeight.w500, color: _lTextHint, letterSpacing: 0.5),
  );

  // ── Dark Theme ──────────────────────────────────────────────────────────
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _ink,
    colorScheme: ColorScheme.dark(
      primary: sosRed,
      onPrimary: Colors.white,
      primaryContainer: sosRed.withValues(alpha: 0.18),
      onPrimaryContainer: sosRed,
      secondary: rescueBlue,
      onSecondary: Colors.white,
      secondaryContainer: rescueBlue.withValues(alpha: 0.18),
      onSecondaryContainer: rescueBlue,
      tertiary: warningAmber,
      onTertiary: Colors.black,
      tertiaryContainer: warningAmber.withValues(alpha: 0.18),
      onTertiaryContainer: warningAmber,
      error: sosRed,
      onError: Colors.white,
      errorContainer: sosRed.withValues(alpha: 0.18),
      onErrorContainer: const Color(0xFFFFB3B3),
      surface: _surface,
      onSurface: _dTextPrimary,
      surfaceContainerLowest: _ink,
      surfaceContainerLow: const Color(0xFF111625),
      surfaceContainer: _surface,
      surfaceContainerHigh: _surfaceVar,
      surfaceContainerHighest: _surfaceHigh,
      onSurfaceVariant: _dTextSecondary,
      outline: _border,
      outlineVariant: _border.withValues(alpha: 0.5),
      shadow: Colors.black,
    ),
    textTheme: _darkText(),
    appBarTheme: AppBarTheme(
      elevation: 0,
      backgroundColor: _surface,
      foregroundColor: _dTextPrimary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.barlowCondensed(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: _dTextPrimary,
        letterSpacing: 1.0,
      ),
      iconTheme: const IconThemeData(color: _dTextPrimary),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border, width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: sosRed,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _dTextPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: _border, width: 1.5),
        textStyle: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: rescueBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceVar,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: sosRed, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: sosRed)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: sosRed, width: 2)),
      hintStyle: const TextStyle(color: _dTextHint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: sosRed,
      foregroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _surfaceVar,
      selectedColor: sosRed.withValues(alpha: 0.25),
      labelStyle: const TextStyle(color: _dTextPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: _border)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _surfaceVar,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: GoogleFonts.barlowCondensed(fontSize: 20, fontWeight: FontWeight.w700, color: _dTextPrimary),
      contentTextStyle: GoogleFonts.barlow(fontSize: 14, color: _dTextSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _surfaceHigh,
      contentTextStyle: GoogleFonts.barlow(color: _dTextPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(color: _border, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: sosRed),
  );

  // ── Light Theme ─────────────────────────────────────────────────────────
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: _lBg,
    colorScheme: ColorScheme.light(
      primary: sosRed,
      onPrimary: Colors.white,
      primaryContainer: sosRed.withValues(alpha: 0.1),
      onPrimaryContainer: sosRed,
      secondary: rescueBlue,
      onSecondary: Colors.white,
      secondaryContainer: rescueBlue.withValues(alpha: 0.1),
      onSecondaryContainer: rescueBlue,
      tertiary: warningAmber,
      onTertiary: Colors.black,
      tertiaryContainer: warningAmber.withValues(alpha: 0.12),
      onTertiaryContainer: const Color(0xFF8A6000),
      error: sosRed,
      onError: Colors.white,
      errorContainer: sosRed.withValues(alpha: 0.1),
      onErrorContainer: const Color(0xFF8B0000),
      surface: _lSurface,
      onSurface: _lTextPrimary,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: _lBg,
      surfaceContainer: _lSurface,
      surfaceContainerHigh: _lSurfaceVar,
      surfaceContainerHighest: const Color(0xFFE5EAFC),
      onSurfaceVariant: _lTextSecondary,
      outline: _lBorder,
      outlineVariant: _lBorder.withValues(alpha: 0.5),
      shadow: const Color(0xFF000000),
    ),
    textTheme: _lightText(),
    appBarTheme: AppBarTheme(
      elevation: 0,
      backgroundColor: _lSurface,
      foregroundColor: _lTextPrimary,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.barlowCondensed(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: _lTextPrimary,
        letterSpacing: 1.0,
      ),
      iconTheme: const IconThemeData(color: _lTextPrimary),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: _lSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _lBorder, width: 1),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: sosRed,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _lTextPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: const BorderSide(color: _lBorder, width: 1.5),
        textStyle: GoogleFonts.barlow(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: rescueBlue,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: GoogleFonts.barlow(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lSurfaceVar,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _lBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: sosRed, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: sosRed)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: sosRed, width: 2)),
      hintStyle: const TextStyle(color: _lTextHint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: sosRed,
      foregroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: _lSurfaceVar,
      selectedColor: sosRed.withValues(alpha: 0.12),
      labelStyle: const TextStyle(color: _lTextPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: _lBorder)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _lSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: GoogleFonts.barlowCondensed(fontSize: 20, fontWeight: FontWeight.w700, color: _lTextPrimary),
      contentTextStyle: GoogleFonts.barlow(fontSize: 14, color: _lTextSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _lTextPrimary,
      contentTextStyle: GoogleFonts.barlow(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(color: _lBorder, thickness: 1, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: sosRed),
  );
}
