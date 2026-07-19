import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/theme/theme_provider.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/generate_totp_code.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/accounts_page.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/circular_countdown_timer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/focus_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'dùng period của account, cache code theo time step và refresh khi resume',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final repository = _MemoryAuthenticatorRepository([
        const AuthenticatorAccount(
          id: 'account-60',
          issuer: 'TEST_ONLY Issuer',
          accountName: 'user@example.invalid',
          secretKey: 'JBSWY3DPEHPK3PXP', // TEST_ONLY synthetic fixture.
          period: 60,
        ),
      ]);
      final accountsBloc = AccountsBloc(
        getAccounts: GetAccounts(repository),
        addAccount: AddAccount(repository),
        deleteAccount: DeleteAccount(repository),
        updateAccount: UpdateAccount(repository),
      );
      final generator = _CountingGenerateTotpCode();
      var now = DateTime.fromMillisecondsSinceEpoch(121000, isUtc: true);

      addTearDown(accountsBloc.close);
      final loaded = accountsBloc.stream.firstWhere(
        (state) => state is AccountsLoaded,
      );
      accountsBloc.add(LoadAccounts());
      await loaded;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeProvider(preferences)),
            BlocProvider.value(value: accountsBloc),
          ],
          child: MaterialApp(
            home: AccountsPage(now: () => now, generateTotpCode: generator),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(accountsBloc.state, isA<AccountsLoaded>());
      expect(find.text('Mã xác thực'), findsOneWidget);
      expect(find.byTooltip('Thêm tài khoản'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Tìm dịch vụ hoặc ứng dụng...'),
        findsOneWidget,
      );
      expect(find.text('TEST_ONLY Issuer'), findsOneWidget);
      var countdown = tester.widget<CircularCountdownTimer>(
        find.byType(CircularCountdownTimer),
      );
      expect(countdown.periodSeconds, 60);
      expect(countdown.secondsRemaining, 59);
      expect(find.text('123 456'), findsOneWidget);
      expect(generator.callCount, 1);
      expect(generator.params.single.timestampMilliseconds, 120000);

      now = DateTime.fromMillisecondsSinceEpoch(122000, isUtc: true);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(generator.callCount, 1);
      countdown = tester.widget<CircularCountdownTimer>(
        find.byType(CircularCountdownTimer),
      );
      expect(countdown.secondsRemaining, 58);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime.fromMillisecondsSinceEpoch(151000, isUtc: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(generator.callCount, 1);
      countdown = tester.widget<CircularCountdownTimer>(
        find.byType(CircularCountdownTimer),
      );
      expect(countdown.secondsRemaining, 29);

      now = DateTime.fromMillisecondsSinceEpoch(180000, isUtc: true);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(generator.callCount, 2);
      expect(generator.params.last.timestampMilliseconds, 180000);
      countdown = tester.widget<CircularCountdownTimer>(
        find.byType(CircularCountdownTimer),
      );
      expect(countdown.secondsRemaining, 60);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'account row pass accessibility/contrast ${themeMode.name} ở text scale 200%',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final repository = _MemoryAuthenticatorRepository([
          const AuthenticatorAccount(
            id: 'accessible-account',
            issuer: 'TEST_ONLY Issuer',
            accountName: 'user@example.invalid',
            secretKey: 'JBSWY3DPEHPK3PXP',
            period: 60,
          ),
        ]);
        final accountsBloc = AccountsBloc(
          getAccounts: GetAccounts(repository),
          addAccount: AddAccount(repository),
          deleteAccount: DeleteAccount(repository),
          updateAccount: UpdateAccount(repository),
        );
        addTearDown(accountsBloc.close);
        final loaded = accountsBloc.stream.firstWhere(
          (state) => state is AccountsLoaded,
        );
        accountsBloc.add(LoadAccounts());
        await loaded;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => ThemeProvider(preferences)),
              BlocProvider.value(value: accountsBloc),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: AccountsPage(
                now: () =>
                    DateTime.fromMillisecondsSinceEpoch(121000, isUtc: true),
                generateTotpCode: _CountingGenerateTotpCode(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final copyAction = find.bySemanticsLabel(
          'Sao chép mã TOTP của TEST_ONLY Issuer, user@example.invalid',
        );
        expect(copyAction, findsOneWidget);
        final copySemantics = tester
            .getSemantics(copyAction)
            .getSemanticsData();
        final spokenCopyContent =
            '${copySemantics.label} ${copySemantics.value}';
        expect(spokenCopyContent, isNot(contains('JBSWY3DPEHPK3PXP')));
        expect(spokenCopyContent, isNot(contains('otpauth')));
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        if (themeMode == ThemeMode.light) {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();

          await pressTab(tester);
          expectPrimaryFocusWithin(find.byTooltip('Đổi giao diện'));
          await pressTab(tester);
          expectPrimaryFocusWithin(find.byTooltip('Thêm tài khoản'));
          await pressTab(tester);
          expectPrimaryFocusWithin(find.byType(TextField));
          await pressTab(tester);
          expectPrimaryFocusWithin(copyAction);

          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(find.text('Đã sao chép mã TOTP.'), findsOneWidget);
        }

        await tester.tap(copyAction);
        await tester.pump();
        expect(find.text('Đã sao chép mã TOTP.'), findsOneWidget);

        await tester.drag(
          find.byKey(const Key('accessible-account')),
          const Offset(-220, 0),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.bySemanticsLabel('QR'), findsOneWidget);
        expect(find.bySemanticsLabel('Sửa'), findsOneWidget);
        expect(find.bySemanticsLabel('Xóa'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(find.byType(TextField), 'issuer');
        await tester.pump();
        expect(find.byTooltip('Xóa nội dung tìm kiếm'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      },
    );
  }
}

class _CountingGenerateTotpCode extends GenerateTotpCode {
  int callCount = 0;
  final List<GenerateTotpCodeParams> params = [];

  @override
  Future<Either<Failure, String>> call(GenerateTotpCodeParams params) async {
    callCount++;
    this.params.add(params);
    return const Right('123456');
  }
}

class _MemoryAuthenticatorRepository implements AuthenticatorRepository {
  _MemoryAuthenticatorRepository(this.accounts);

  final List<AuthenticatorAccount> accounts;

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List.unmodifiable(accounts));

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Unit>> updateAccount(AuthenticatorAccount account) {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> accounts,
  ) {
    throw UnimplementedError();
  }
}
