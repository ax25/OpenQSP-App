import 'package:flutter/material.dart';

abstract final class OpenQspColors {
  static const background = Color(0xFFF5F4F0);
  static const surface = Color(0xFFFFFFFF);
  static const primaryText = Color(0xFF202326);
  static const secondaryText = Color(0xFF667078);
  static const brand = Color(0xFF245E66);
  static const border = Color(0xFFCBD1D5);
}

abstract final class OpenQspTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: OpenQspColors.brand,
      onPrimary: Colors.white,
      surface: OpenQspColors.surface,
      onSurface: OpenQspColors.primaryText,
      outline: OpenQspColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: OpenQspColors.background,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: OpenQspColors.primaryText,
          fontSize: 40,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        titleMedium: TextStyle(
          color: OpenQspColors.primaryText,
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: OpenQspColors.surface,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: TextStyle(
          color: OpenQspColors.secondaryText,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: OpenQspColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: OpenQspColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: OpenQspColors.brand, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: OpenQspColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: OpenQspColors.brand.withValues(alpha: 0.38),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
