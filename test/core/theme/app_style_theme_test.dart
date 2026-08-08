import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_style_palette.dart';
import 'package:hyper_authenticator/core/theme/app_style_tokens.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';

void main() {
  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.light
          ? AppTheme.light(style)
          : AppTheme.dark(style);
      final palette = AppStylePalette.of(style, brightness);
      final label = '${style.name}/${brightness.name}';

      test('$label áp palette vào scaffold, primary và card', () {
        expect(theme.brightness, brightness);
        expect(theme.scaffoldBackgroundColor, palette.background);
        expect(theme.colorScheme.primary, palette.primary);
        expect(theme.colorScheme.onPrimary, palette.onPrimary);
        expect(theme.cardTheme.color, palette.surfaceCard);
        final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
        expect(
          cardShape.borderRadius,
          BorderRadius.circular(palette.cardRadius),
        );
      });

      test('$label expose AppStyleTokens cho widget TOTP', () {
        final tokens = theme.extension<AppStyleTokens>();
        expect(tokens, isNotNull);
        expect(tokens!.countdownColor, palette.primary);
        expect(tokens.countdownWarnColor, palette.countdownWarn);
        // Token luôn concrete và opaque; token null sẽ lerp thành transparent
        // khi đổi theme và làm mã OTP biến mất.
        expect(tokens.otpCodeColor, palette.otpCode ?? palette.textPrimary);
        expect(tokens.otpCodeColor.a, 1.0);
      });
    }
  }

  test('OLED dark dùng nền đen tuyền và mã OTP màu accent', () {
    final theme = AppTheme.dark(AppStyle.oledDark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    final tokens = theme.extension<AppStyleTokens>()!;
    expect(tokens.otpCodeColor, theme.colorScheme.primary);
  });

  test('alias mặc định trỏ về Security Minimal', () {
    expect(
      AppTheme.lightTheme.colorScheme.primary,
      AppStylePalette.of(AppStyle.securityMinimal, Brightness.light).primary,
    );
    expect(
      AppTheme.darkTheme.colorScheme.primary,
      AppStylePalette.of(AppStyle.securityMinimal, Brightness.dark).primary,
    );
  });
}
