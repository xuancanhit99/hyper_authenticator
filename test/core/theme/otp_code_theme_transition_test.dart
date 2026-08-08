import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_style_palette.dart';
import 'package:hyper_authenticator/core/theme/app_style_tokens.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_code_tile.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/circular_countdown_timer.dart';

// Regression cho P1: token OTP nullable từng lerp về transparent khi đổi
// style, làm mã biến mất sau animation OLED Dark -> style khác.
void main() {
  const account = AuthenticatorAccount(
    id: 'transition-account',
    issuer: 'TEST_ONLY Issuer',
    accountName: 'user@example.invalid',
    secretKey: 'JBSWY3DPEHPK3PXP', // TEST_ONLY synthetic fixture.
  );

  test('ThemeData.lerp giữa OLED và style khác giữ mã OTP opaque', () {
    final from = AppTheme.dark(AppStyle.oledDark);
    final to = AppTheme.dark(AppStyle.securityMinimal);

    for (final t in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final tokens = ThemeData.lerp(from, to, t).extension<AppStyleTokens>();
      expect(tokens, isNotNull, reason: 't=$t');
      expect(tokens!.otpCodeColor.a, 1.0, reason: 't=$t');
    }

    final settled = ThemeData.lerp(from, to, 1.0).extension<AppStyleTokens>()!;
    expect(
      settled.otpCodeColor,
      AppStylePalette.of(AppStyle.securityMinimal, Brightness.dark).textPrimary,
    );
  });

  testWidgets('đổi style OLED -> Minimal: mã OTP vẫn nhìn thấy sau animation', (
    tester,
  ) async {
    Widget buildApp(AppStyle style) {
      return MaterialApp(
        theme: AppTheme.dark(style),
        home: Scaffold(
          body: AccountCodeTile(
            account: account,
            displayCode: '123 456',
            timeWindow: const TotpTimeWindow(timeStep: 1, secondsRemaining: 20),
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      );
    }

    Color codeColor() {
      final text = tester.widget<Text>(
        find.byKey(const Key('account-code-${'transition-account'}')),
      );
      return text.style!.color!;
    }

    await tester.pumpWidget(buildApp(AppStyle.oledDark));
    expect(
      codeColor(),
      AppStylePalette.of(AppStyle.oledDark, Brightness.dark).otpCode,
    );

    await tester.pumpWidget(buildApp(AppStyle.securityMinimal));
    await tester.pump(const Duration(milliseconds: 100));
    expect(codeColor().a, 1.0, reason: 'giữa animation không được transparent');

    await tester.pumpAndSettle();
    expect(
      codeColor(),
      AppStylePalette.of(AppStyle.securityMinimal, Brightness.dark).textPrimary,
    );
    expect(codeColor().a, 1.0);
  });
}
