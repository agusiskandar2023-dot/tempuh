import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF0B1220);
  static const charcoal = Color(0xFF172033);
  static const card = Color(0xFF1E293B);
  static const lime = Color(0xFFA3E635);
  static const route = Color(0xFFA3E635);
  static const muted = Color(0xFF94A3B8);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.lime,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.lime,
    onPrimary: AppColors.navy,
    surface: AppColors.charcoal,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.navy,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.charcoal,
      indicatorColor: Color(0x33A3E635),
    ),
  );
}
