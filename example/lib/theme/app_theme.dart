import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Minimal black & white theme
class AppTheme {
  // Colors
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const gray = Color(0xFF666666);
  static const lightGray = Color(0xFFCCCCCC);
  static const background = Color(0xFFF5F5F5);

  static ThemeData get theme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: white,
      primaryColor: black,
      colorScheme: const ColorScheme.light(
        primary: black,
        secondary: black,
        surface: white,
        background: white,
      ),
      
      // App bar
      appBarTheme: const AppBarTheme(
        backgroundColor: white,
        foregroundColor: black,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: black,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
      ),
      
      // Text
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: black,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        headlineMedium: TextStyle(
          color: black,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        bodyLarge: TextStyle(
          color: black,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          color: gray,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: black,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      
      // Floating action button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: black,
        foregroundColor: white,
        elevation: 0,
        shape: CircleBorder(),
      ),
      
      // Card
      cardTheme: CardTheme(
        color: white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: lightGray, width: 1),
        ),
      ),
      
      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: lightGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: black, width: 2),
        ),
        hintStyle: const TextStyle(color: gray),
      ),
      
      // Checkbox
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return black;
          }
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(white),
        side: const BorderSide(color: lightGray, width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      
      // Divider
      dividerTheme: const DividerThemeData(
        color: lightGray,
        thickness: 1,
      ),
    );
  }
}
