import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4056A1)),
  );
}
