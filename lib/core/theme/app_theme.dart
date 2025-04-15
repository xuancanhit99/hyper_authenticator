// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/constants/app_colors.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/elevated_button_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/outlined_button_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/text_field_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/text_theme.dart'; // Import custom colors

class AppTheme {
  // Prevent instantiation
  AppTheme._();

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true, // Enable Material 3 features
    brightness: Brightness.light,
    // primarySwatch: Colors.blue, // Not needed when using ColorScheme.fromSeed effectively
    primaryColor: AppColors.facebookBlue, // Use Facebook blue
    scaffoldBackgroundColor:
        AppColors.lightBackground, // White or light gray background
    fontFamily: 'Averta', // Set default font
    appBarTheme: AppBarTheme(
      // Facebook style AppBar (usually light)
      backgroundColor: AppColors.lightBackground, // White or light gray
      foregroundColor: AppColors.textPrimaryLight, // Dark title and icons
      elevation: 0.5, // Subtle elevation or 0
      titleTextStyle: TextStyle(
          color: AppColors.textPrimaryLight,
          fontSize: 20,
          fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: AppColors.textPrimaryLight),
    ),
    textTheme: CTextTheme.lightTextTheme,
    outlinedButtonTheme: COutlinedButtonTheme.lightOutlinedButtonTheme,
    elevatedButtonTheme: CElevatedButtonTheme.lightElevatedButtonTheme,
    inputDecorationTheme: CTextFormFieldTheme.lightInputDecorationTheme,
    // elevatedButtonTheme: ElevatedButtonThemeData(
    //   style: ElevatedButton.styleFrom(
    //     backgroundColor: AppColors.facebookBlue, // Facebook blue button
    //     foregroundColor: Colors.white, // White text on button
    //     shape: RoundedRectangleBorder(
    //       borderRadius: BorderRadius.circular(8.0),
    //     ),
    //     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    //   ),
    // ),
    // inputDecorationTheme: InputDecorationTheme(
    //   border: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(8.0),
    //     borderSide: BorderSide(color: Colors.grey[400]!),
    //   ),
    //   focusedBorder: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(8.0),
    //     borderSide: BorderSide(
    //         color: AppColors.facebookBlue,
    //         width: 2.0), // Facebook blue focus border
    //   ),
    //   labelStyle: TextStyle(
    //       color:
    //           AppColors.textSecondaryLight), // Use defined secondary text color
    // ),
    // Add other theme properties as needed (textTheme, cardTheme, etc.)
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.facebookBlue, // Use Facebook blue as seed
      brightness: Brightness.light,
      // Override specific scheme colors if needed
      primary: AppColors.facebookBlue,
      background: AppColors.lightBackground,
      surface: AppColors.lightBackground,
      onBackground: AppColors.textPrimaryLight,
      onSurface: AppColors.textPrimaryLight,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    // primarySwatch: Colors.blue,
    primaryColor:
        AppColors.facebookBlue, // Use Facebook blue (adjust if needed for dark)
    scaffoldBackgroundColor:
        AppColors.darkBackground, // Use defined dark background
    fontFamily: 'Averta', // Set default font
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.darkSurface, // Use defined dark surface
      foregroundColor: AppColors.textPrimaryDark, // Light title and icons
      elevation: 0.5, // Subtle elevation or 0
      titleTextStyle: TextStyle(
          color: AppColors.textPrimaryDark,
          fontSize: 20,
          fontWeight: FontWeight.bold),
      iconTheme: IconThemeData(color: AppColors.textPrimaryDark),
    ),
    textTheme: CTextTheme.darkTextTheme,
    outlinedButtonTheme: COutlinedButtonTheme.darkOutlinedButtonTheme,
    elevatedButtonTheme: CElevatedButtonTheme.darkElevatedButtonTheme,
    inputDecorationTheme: CTextFormFieldTheme.darkInputDecorationTheme,
    // elevatedButtonTheme: ElevatedButtonThemeData(
    //   style: ElevatedButton.styleFrom(
    //     backgroundColor: AppColors.facebookBlue, // Facebook blue button
    //     foregroundColor: Colors.white, // White text on button
    //     shape: RoundedRectangleBorder(
    //       borderRadius: BorderRadius.circular(8.0),
    //     ),
    //     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    //   ),
    // ),
    // inputDecorationTheme: InputDecorationTheme(
    //   border: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(8.0),
    //     borderSide: BorderSide(color: Colors.grey[700]!),
    //   ),
    //   focusedBorder: OutlineInputBorder(
    //     borderRadius: BorderRadius.circular(8.0),
    //     borderSide: BorderSide(
    //         color: AppColors.facebookBlue,
    //         width: 2.0), // Facebook blue focus border
    //   ),
    //   labelStyle: TextStyle(
    //       color:
    //           AppColors.textSecondaryDark), // Use defined secondary text color
    //   hintStyle: TextStyle(color: AppColors.textSecondaryDark.withOpacity(0.7)),
    //   // Ensure prefix/suffix icon colors contrast well
    //   iconColor: AppColors.textSecondaryDark,
    //   prefixIconColor: AppColors.textSecondaryDark,
    //   suffixIconColor: AppColors.textSecondaryDark,
    // ),
    // Add other theme properties
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.facebookBlue, // Use Facebook blue as seed
      brightness: Brightness.dark,
      // Override specific scheme colors for better dark theme control
      primary: AppColors.facebookBlue, // Keep primary blue
      background: AppColors.darkBackground,
      surface: AppColors.darkSurface,
      onPrimary: Colors.white, // Text on primary color button
      onBackground: AppColors.textPrimaryDark,
      onSurface: AppColors.textPrimaryDark,
      // You might need to adjust secondary, error colors etc. based on the seed generation
    ),
  );
}
