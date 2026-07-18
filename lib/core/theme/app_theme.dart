// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/constants/app_colors.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/elevated_button_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/outlined_button_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/text_field_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/text_theme.dart';

class AppTheme {
  // Prevent instantiation
  AppTheme._();

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: AppColors.primaryLight,
    scaffoldBackgroundColor: AppColors.lightBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.lightBackground,
      foregroundColor: AppColors.textPrimaryLight,
      elevation: 0.5,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimaryLight,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimaryLight),
    ),
    textTheme: CTextTheme.lightTextTheme,
    outlinedButtonTheme: COutlinedButtonTheme.lightOutlinedButtonTheme,
    elevatedButtonTheme: CElevatedButtonTheme.lightElevatedButtonTheme,
    inputDecorationTheme: CTextFormFieldTheme.lightInputDecorationTheme,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.lightBackground,
      indicatorColor: AppColors.primaryLight.withValues(alpha: 0.15),
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLight,
          );
        }
        return TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondaryLight,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: AppColors.primaryLight);
        }
        return IconThemeData(color: AppColors.textSecondaryLight);
      }),
      elevation: 0,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primaryLight,
      brightness: Brightness.light,
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      surface: AppColors.lightBackground,
      onSurface: AppColors.textPrimaryLight,
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: AppColors.primaryDark,
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.cDarkColor,
      foregroundColor: AppColors.textPrimaryDark,
      elevation: 0.5,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimaryDark,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimaryDark),
    ),
    // Set color cDarkColor for background bottomNavigationBar
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cDarkColor,
      indicatorColor: AppColors.primaryDark.withValues(alpha: 0.25),
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryDark,
          );
        }
        return TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondaryDark,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: AppColors.primaryDark);
        }
        return IconThemeData(color: AppColors.textSecondaryDark);
      }),
      elevation: 0,
    ),
    textTheme: CTextTheme.darkTextTheme,
    outlinedButtonTheme: COutlinedButtonTheme.darkOutlinedButtonTheme,
    elevatedButtonTheme: CElevatedButtonTheme.darkElevatedButtonTheme,
    inputDecorationTheme: CTextFormFieldTheme.darkInputDecorationTheme,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primaryDark,
      brightness: Brightness.dark,
      primary: AppColors.primaryDark,
      surface: AppColors.darkSurface,
      onPrimary: AppColors.onPrimaryDark,
      onSurface: AppColors.textPrimaryDark,
    ),
  );
}
