import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';

/// Resolved visual tokens for one [AppStyle] × [Brightness] combination.
///
/// [AppTheme] consumes these instead of reading [AppColors] directly so every
/// style stays a pure data swap on top of the same widget structure.
@immutable
class AppStylePalette {
  const AppStylePalette({
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.surfaceCard,
    required this.textPrimary,
    required this.textSecondary,
    required this.countdownWarn,
    this.otpCode,
    this.cardRadius = 16,
    this.controlRadius = 20,
    this.dialogRadius = 24,
    this.sheetRadius = 28,
  });

  final Color primary;
  final Color onPrimary;

  /// Scaffold + app bar + navigation bar background.
  final Color background;

  /// Card / elevated surface color.
  final Color surfaceCard;

  final Color textPrimary;
  final Color textSecondary;

  /// Countdown color for the last seconds of a TOTP window.
  final Color countdownWarn;

  /// Explicit OTP code color. Null means "no accent code color": [AppTheme]
  /// maps it to [textPrimary] when building [AppStyleTokens] so the token
  /// stays non-null and theme lerp never passes through transparent.
  final Color? otpCode;

  final double cardRadius;
  final double controlRadius;
  final double dialogRadius;
  final double sheetRadius;

  static AppStylePalette of(AppStyle style, Brightness brightness) {
    return switch ((style, brightness)) {
      (AppStyle.securityMinimal, Brightness.light) => _minimalLight,
      (AppStyle.securityMinimal, Brightness.dark) => _minimalDark,
      (AppStyle.oledDark, Brightness.light) => _oledLight,
      (AppStyle.oledDark, Brightness.dark) => _oledDark,
      (AppStyle.darkCinema, Brightness.light) => _cinemaLight,
      (AppStyle.darkCinema, Brightness.dark) => _cinemaDark,
    };
  }

  // Light-mode greens sit at 700-tone so 14 px text passes WCAG 4.5:1 both as
  // foreground on tinted dialog surfaces and as button fill under white text.
  static const _minimalLight = AppStylePalette(
    primary: Color(0xFF0F6E4C),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFFAFAF8),
    surfaceCard: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF182019),
    textSecondary: Color(0xFF59615B),
    countdownWarn: Color(0xFFB35F00),
  );

  static const _minimalDark = AppStylePalette(
    primary: Color(0xFF3CC88B),
    onPrimary: Color(0xFF06281C),
    background: Color(0xFF121212),
    surfaceCard: Color(0xFF1D1F1D),
    textPrimary: Color(0xFFECEFEC),
    textSecondary: Color(0xFFAEB6B0),
    countdownWarn: Color(0xFFF0B455),
  );

  static const _oledLight = AppStylePalette(
    primary: Color(0xFF0F6E4C),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFFFFFFF),
    surfaceCard: Color(0xFFF6F7F5),
    textPrimary: Color(0xFF182019),
    textSecondary: Color(0xFF59615B),
    countdownWarn: Color(0xFFB35F00),
  );

  static const _oledDark = AppStylePalette(
    primary: Color(0xFF4ADE97),
    onPrimary: Color(0xFF04241A),
    background: Color(0xFF000000),
    surfaceCard: Color(0xFF121212),
    textPrimary: Color(0xFFF2F4F2),
    textSecondary: Color(0xFF98A09B),
    countdownWarn: Color(0xFFFAC775),
    otpCode: Color(0xFF4ADE97),
  );

  static const _cinemaLight = AppStylePalette(
    primary: Color(0xFF4F5ABF),
    onPrimary: Color(0xFFFFFFFF),
    background: Color(0xFFF6F6FB),
    surfaceCard: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1A1B26),
    textSecondary: Color(0xFF64687A),
    countdownWarn: Color(0xFFAD5F16),
    cardRadius: 18,
  );

  static const _cinemaDark = AppStylePalette(
    primary: Color(0xFF7C87E8),
    onPrimary: Color(0xFF10122B),
    background: Color(0xFF0A0A12),
    surfaceCard: Color(0xFF171724),
    textPrimary: Color(0xFFEDEDF2),
    textSecondary: Color(0xFF9BA0AF),
    countdownWarn: Color(0xFFF0B37E),
    cardRadius: 18,
  );
}
