import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF00afef);
  static const Color accentBlue = Color(0xFF0077C0);
  static const Color lightBlue = Color(0xFFF0F9FD);
  static const Color textPrimary = Color(0xFF0A2540);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.white,

      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        secondary: accentBlue,
        surface: Colors.white,
      ),

      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
      ),

      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
        titleMedium: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
        bodyMedium: TextStyle(color: Colors.blueGrey),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBlue.withValues(alpha: 0.35),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: accentBlue, width: 1.3)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(90, 37),
          padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
