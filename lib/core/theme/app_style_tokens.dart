import 'package:flutter/material.dart';

/// Style-specific tokens that Material's [ColorScheme] cannot express,
/// exposed to widgets via `Theme.of(context).extension<AppStyleTokens>()`.
@immutable
class AppStyleTokens extends ThemeExtension<AppStyleTokens> {
  const AppStyleTokens({
    required this.countdownColor,
    required this.countdownWarnColor,
    required this.otpCodeColor,
  });

  /// Countdown indicator color during the normal part of a TOTP window.
  final Color countdownColor;

  /// Countdown indicator color for the final seconds of a TOTP window.
  final Color countdownWarnColor;

  /// OTP code color. Always concrete: styles without an accent code color set
  /// this to their primary text color. A nullable token would make
  /// `Color.lerp(color, null, 1)` resolve to transparent during theme
  /// animation and render codes invisible.
  final Color otpCodeColor;

  @override
  AppStyleTokens copyWith({
    Color? countdownColor,
    Color? countdownWarnColor,
    Color? otpCodeColor,
  }) {
    return AppStyleTokens(
      countdownColor: countdownColor ?? this.countdownColor,
      countdownWarnColor: countdownWarnColor ?? this.countdownWarnColor,
      otpCodeColor: otpCodeColor ?? this.otpCodeColor,
    );
  }

  @override
  AppStyleTokens lerp(ThemeExtension<AppStyleTokens>? other, double t) {
    if (other is! AppStyleTokens) return this;
    return AppStyleTokens(
      countdownColor: Color.lerp(countdownColor, other.countdownColor, t)!,
      countdownWarnColor: Color.lerp(
        countdownWarnColor,
        other.countdownWarnColor,
        t,
      )!,
      otpCodeColor: Color.lerp(otpCodeColor, other.otpCodeColor, t)!,
    );
  }
}
