import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const background = Color(0xFF121316);
  static const surface = Color(0xFF1B1D22);
  static const selected = Color(0xFF292B31);
  static const text = Color(0xFFF4EFE6);
  static const muted = Color(0xFFBEB8AE);
  static const accent = Color(0xFFFF6B5E);

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    colorScheme: const ColorScheme.dark(
      primary: accent,
      onPrimary: background,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      error: Color(0xFFFF6B6B),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: selected,
      circularTrackColor: selected,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}
