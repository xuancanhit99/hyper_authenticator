// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_style_palette.dart';
import 'package:hyper_authenticator/core/theme/app_style_tokens.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/elevated_button_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/filled_button_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/outlined_button_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/text_field_theme.dart';
import 'package:hyper_authenticator/core/theme/widget_themes/text_theme.dart';

class AppTheme {
  // Prevent instantiation
  AppTheme._();

  static ThemeData light([AppStyle style = AppStyle.securityMinimal]) =>
      _build(style, Brightness.light);

  static ThemeData dark([AppStyle style = AppStyle.securityMinimal]) =>
      _build(style, Brightness.dark);

  /// Default-style aliases kept for tests and call sites that do not care
  /// about the selected [AppStyle].
  static ThemeData get lightTheme => light();
  static ThemeData get darkTheme => dark();

  static ThemeData _build(AppStyle style, Brightness brightness) {
    final palette = AppStylePalette.of(style, brightness);
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: palette.primary,
      scaffoldBackgroundColor: palette.background,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        elevation: 0.5,
        titleTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      textTheme: isLight ? CTextTheme.lightTextTheme : CTextTheme.darkTextTheme,
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        color: palette.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(palette.cardRadius),
        ),
      ),
      outlinedButtonTheme: COutlinedButtonTheme.themed(
        primary: palette.primary,
        radius: palette.controlRadius,
      ),
      elevatedButtonTheme: CElevatedButtonTheme.themed(
        primary: palette.primary,
        onPrimary: palette.onPrimary,
        radius: palette.controlRadius,
      ),
      filledButtonTheme: CFilledButtonTheme.filledButtonTheme,
      inputDecorationTheme: CTextFormFieldTheme.themed(
        primary: palette.primary,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.background,
        indicatorColor: palette.primary.withValues(
          alpha: isLight ? 0.15 : 0.25,
        ),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: palette.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: palette.primary);
          }
          return IconThemeData(color: palette.textSecondary);
        }),
        elevation: 0,
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
        primary: palette.primary,
        onPrimary: palette.onPrimary,
        surface: palette.background,
        onSurface: palette.textPrimary,
        onSurfaceVariant: palette.textSecondary,
      ),
      extensions: [
        AppStyleTokens(
          countdownColor: palette.primary,
          countdownWarnColor: palette.countdownWarn,
          otpCodeColor: palette.otpCode ?? palette.textPrimary,
        ),
      ],
    );
  }
}
