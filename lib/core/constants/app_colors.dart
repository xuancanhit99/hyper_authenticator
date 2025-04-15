import 'package:flutter/material.dart';

// Define custom colors used throughout the application

class AppColors {
  // Prevent instantiation
  AppColors._();

  // --- Primary Colors ---
  static const Color facebookBlue = Color(0xFF1877F2);

  // --- Neutral Colors ---
  static const Color lightBackground =
      Color(0xFFFFFFFF); // Or Color(0xFFF0F2F5) for light gray
  static const Color darkBackground = Color(0xFF1C1E21); // Example dark bg
  static const Color darkSurface = Color(0xFF242526); // Example dark surface

  // --- Text Colors ---
  static const Color textPrimaryLight =
      Color(0xFF050505); // Dark text on light bg
  static const Color textSecondaryLight =
      Color(0xFF65676B); // Gray text on light bg
  static const Color textPrimaryDark =
      Color(0xFFE4E6EB); // Light text on dark bg
  static const Color textSecondaryDark =
      Color(0xFFB0B3B8); // Gray text on dark bg

  // Add other colors as needed (e.g., error, success, warning)
  static const Color error = Colors.red;


  // static const cPrimaryColor = Color(0xFFFFE400);
  static const cPrimaryColor = Color(0xFF3cc88b);
  static const cSecondaryColor= Color(0xFF272727);
  static const cAccentColor = Color(0xFF001BFF);

  static const cCardBgColor = Color(0xFFF7F6F1);
  static const cWhiteColor = Color(0xFFFFFFFF);
  static const cDarkColor = Color(0xFF000000);
}
