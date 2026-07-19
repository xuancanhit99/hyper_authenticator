import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../support/focus_test_utils.dart';

void main() {
  testWidgets(
    'scanner pending hiển thị hướng dẫn cấp quyền thay vì màn hình đen',
    (tester) async {
      final controller = _FakeScannerController();
      final accountsBloc = _accountsBloc();
      addTearDown(accountsBloc.close);

      await _pumpPage(tester, accountsBloc, controller);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Thêm tài khoản'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Quét mã QR'));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Quét mã QR'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(AddAccountPage.scannerLoadingKey), findsOneWidget);
      expect(find.text('Đang khởi động camera…'), findsOneWidget);
      expect(find.textContaining('hãy chọn Cho phép'), findsOneWidget);
      expect(controller.startCount, 1);
    },
  );

  testWidgets(
    'scanner permission denied cho retry hoặc quay lại nhập thủ công',
    (tester) async {
      final controller = _FakeScannerController(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
      final accountsBloc = _accountsBloc();
      addTearDown(accountsBloc.close);

      await _pumpPage(tester, accountsBloc, controller);
      await tester.tap(find.byTooltip('Quét mã QR'));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(AddAccountPage.scannerErrorKey), findsOneWidget);
      expect(find.textContaining('chưa có quyền dùng camera'), findsOneWidget);

      await tester.tap(find.byKey(AddAccountPage.scannerRetryKey));
      await tester.pump();
      expect(controller.startCount, 2);

      await tester.tap(find.byKey(AddAccountPage.scannerManualEntryKey));
      await tester.pump();
      expect(find.byKey(AddAccountPage.issuerFieldKey), findsOneWidget);
      expect(controller.stopCount, 2);
    },
  );

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'form thêm account pass accessibility/contrast ${themeMode.name} ở text scale 200%',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _FakeScannerController();
        final accountsBloc = _accountsBloc();
        addTearDown(accountsBloc.close);

        await _pumpPage(
          tester,
          accountsBloc,
          controller,
          textScaler: const TextScaler.linear(2),
          themeMode: themeMode,
        );

        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      },
    );
  }

  testWidgets('manual entry keyboard traversal và submit không cần pointer', (
    tester,
  ) async {
    final controller = _FakeScannerController();
    final repository = _MemoryAuthenticatorRepository();
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await _pumpPage(tester, accountsBloc, controller);

    final issuerField = find.byKey(AddAccountPage.issuerFieldKey);
    final accountNameField = find.byKey(AddAccountPage.accountNameFieldKey);
    final secretField = find.byKey(AddAccountPage.secretFieldKey);
    final submit = find.byKey(AddAccountPage.submitButtonKey);

    await tester.tap(issuerField);
    await tester.enterText(issuerField, 'TEST_ONLY Issuer');
    expectPrimaryFocusWithin(issuerField);

    await pressTab(tester);
    expectPrimaryFocusWithin(accountNameField);
    await tester.enterText(accountNameField, 'user@example.invalid');

    await pressTab(tester);
    expectPrimaryFocusWithin(secretField);
    await tester.enterText(secretField, 'JBSWY3DPEHPK3PXP');

    await pressTab(tester);
    expectPrimaryFocusWithin(submit);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      repository.addedAccount,
      const AuthenticatorAccount(
        id: 'keyboard-account',
        issuer: 'TEST_ONLY Issuer',
        accountName: 'user@example.invalid',
        secretKey: 'JBSWY3DPEHPK3PXP',
      ),
    );
  });

  testWidgets('chỉ đóng add route sau success đúng operation', (tester) async {
    final controller = _FakeScannerController();
    final repository = _MemoryAuthenticatorRepository();
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: accountsBloc,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AddAccountPage(scannerController: controller),
                  ),
                ),
                child: const Text('Mở form test'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở form test'));
    await tester.pumpAndSettle();

    accountsBloc.add(LoadAccounts());
    await tester.pumpAndSettle();
    expect(find.byType(AddAccountPage), findsOneWidget);

    await tester.enterText(
      find.byKey(AddAccountPage.issuerFieldKey),
      'TEST_ONLY Route',
    );
    await tester.enterText(
      find.byKey(AddAccountPage.accountNameFieldKey),
      'route@example.invalid',
    );
    await tester.enterText(
      find.byKey(AddAccountPage.secretFieldKey),
      'JBSWY3DPEHPK3PXP',
    );
    await tester.tap(find.byKey(AddAccountPage.submitButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(AddAccountPage), findsNothing);
    expect(find.text('Mở form test'), findsOneWidget);
    expect(find.text('Đã thêm tài khoản.'), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  AccountsBloc accountsBloc,
  MobileScannerController controller, {
  TextScaler? textScaler,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.pumpWidget(
    BlocProvider.value(
      value: accountsBloc,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
        home: AddAccountPage(scannerController: controller),
      ),
    ),
  );
}

AccountsBloc _accountsBloc([AuthenticatorRepository? repository]) {
  repository ??= _MemoryAuthenticatorRepository();
  return AccountsBloc(
    getAccounts: GetAccounts(repository),
    addAccount: AddAccount(repository),
    deleteAccount: DeleteAccount(repository),
    updateAccount: UpdateAccount(repository),
  );
}

class _FakeScannerController extends MobileScannerController {
  _FakeScannerController({this.errorCode}) : super(autoStart: false);

  final MobileScannerErrorCode? errorCode;
  int startCount = 0;
  int stopCount = 0;

  @override
  Future<void> start({
    CameraFacing? cameraDirection,
    CameraLensType? cameraLensType,
  }) async {
    startCount++;
    if (errorCode case final code?) {
      value = MobileScannerState(
        availableCameras: 0,
        cameraDirection: CameraFacing.unknown,
        cameraLensType: CameraLensType.any,
        error: MobileScannerException(errorCode: code),
        isInitialized: true,
        isStarting: false,
        isRunning: false,
        size: Size.zero,
        torchState: TorchState.unavailable,
        zoomScale: 1,
        deviceOrientation: DeviceOrientation.portraitUp,
      );
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    try {
      await super.dispose();
    } on MissingPluginException {
      // Widget test không đăng ký camera platform plugin.
    }
  }
}

class _MemoryAuthenticatorRepository implements AuthenticatorRepository {
  AuthenticatorAccount? addedAccount;

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(addedAccount == null ? const [] : [addedAccount!]);

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) async {
    addedAccount = AuthenticatorAccount(
      id: 'keyboard-account',
      issuer: issuer,
      accountName: accountName,
      secretKey: secretKey,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
    return Right(addedAccount!);
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
