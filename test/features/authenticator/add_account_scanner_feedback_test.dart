import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/add_account_page.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/totp_import_preview_dialog.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../support/focus_test_utils.dart';

const _googleSingleBatchUri =
    'otpauth-migration://offline?data='
    'CkIKElRFU1RfT05MWV9TRUNSRVRfQRIdRXhhbXBsZTphbGljZUBleGFtcGxlLmludm'
    'FsaWQaB0V4YW1wbGUgASgBMAIKPQoSVEVTVF9PTkxZX1NFQ1JFVF9CEhNib2JAZXhh'
    'bXBsZS5pbnZhbGlkGgxFeGFtcGxlIExhYnMgAigCMAIQARgBIAAokiE%3D';
const _googleBatchPartZeroUri =
    'otpauth-migration://offline?data='
    'CkIKElRFU1RfT05MWV9TRUNSRVRfQRIdRXhhbXBsZTphbGljZUBleGFtcGxlLmludm'
    'FsaWQaB0V4YW1wbGUgASgBMAIQARgCIAAokyE%3D';
const _googleBatchPartOneUri =
    'otpauth-migration://offline?data='
    'Cj0KElRFU1RfT05MWV9TRUNSRVRfQhITYm9iQGV4YW1wbGUuaW52YWxpZBoMRXhhbX'
    'BsZSBMYWJzIAIoAjACEAEYAiABKJMh';
const _standardTotpUri =
    'otpauth://totp/TEST_ONLY%20Standard:user%40example.invalid'
    '?secret=JBSWY3DPEHPK3PXP&issuer=TEST_ONLY%20Standard'
    '&algorithm=SHA256&digits=8&period=60';

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
          matching: find.text('Thêm mã xác thực'),
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
      expect(find.textContaining('cho phép truy cập camera'), findsOneWidget);
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
      expect(find.textContaining('Chưa có quyền dùng camera'), findsOneWidget);

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
    expectPrimaryFocusWithin(find.byTooltip('Hiện khóa thiết lập'));
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

  testWidgets('secret key được che mặc định và chỉ hiện theo yêu cầu', (
    tester,
  ) async {
    final controller = _FakeScannerController();
    final accountsBloc = _accountsBloc();
    addTearDown(accountsBloc.close);

    await _pumpPage(tester, accountsBloc, controller);

    final secretInput = find.descendant(
      of: find.byKey(AddAccountPage.secretFieldKey),
      matching: find.byType(EditableText),
    );
    var secretField = tester.widget<EditableText>(secretInput);
    expect(secretField.obscureText, isTrue);
    expect(secretField.autocorrect, isFalse);
    expect(secretField.enableSuggestions, isFalse);
    expect(secretField.enableIMEPersonalizedLearning, isFalse);

    await tester.tap(find.byTooltip('Hiện khóa thiết lập'));
    await tester.pump();

    secretField = tester.widget<EditableText>(secretInput);
    expect(secretField.obscureText, isFalse);
    expect(find.byTooltip('Ẩn khóa thiết lập'), findsOneWidget);
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
    expect(find.text('Đã thêm mã xác thực.'), findsOneWidget);
  });

  testWidgets(
    'Google migration chỉ import sau preview confirm và không render secret',
    (tester) async {
      final controller = _FakeScannerController();
      final repository = _MemoryAuthenticatorRepository();
      final accountsBloc = _accountsBloc(repository);
      addTearDown(accountsBloc.close);

      await _pumpPage(tester, accountsBloc, controller);
      await tester.tap(find.byTooltip('Quét mã QR'));
      await tester.pump();
      _scan(tester, _googleSingleBatchUri);
      await tester.pumpAndSettle();

      expect(find.text('Kiểm tra mã sẽ nhập'), findsOneWidget);
      expect(find.text('Example'), findsOneWidget);
      expect(find.textContaining('alice@example.invalid'), findsOneWidget);
      expect(find.textContaining('KRCVGVC7'), findsNothing);
      expect(find.textContaining('otpauth-migration'), findsNothing);
      expect(repository.importCallCount, 0);

      await tester.drag(
        find.byKey(TotpImportPreviewDialog.accountListKey),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(find.text('Example Labs'), findsOneWidget);
      expect(find.textContaining('bob@example.invalid'), findsOneWidget);

      await tester.tap(find.byKey(TotpImportPreviewDialog.confirmButtonKey));
      await tester.pumpAndSettle();

      expect(repository.importCallCount, 1);
      expect(repository.importedAccounts, hasLength(2));
      expect(find.text('Đã nhập 2 mã.'), findsOneWidget);
    },
  );

  testWidgets('standard otpauth cancel preview không mutate repository', (
    tester,
  ) async {
    final controller = _FakeScannerController();
    final repository = _MemoryAuthenticatorRepository();
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await _pumpPage(tester, accountsBloc, controller);
    await tester.tap(find.byTooltip('Quét mã QR'));
    await tester.pump();
    _scan(tester, _standardTotpUri);
    await tester.pumpAndSettle();

    expect(find.text('Kiểm tra mã sẽ nhập'), findsOneWidget);
    expect(find.text('TEST_ONLY Standard'), findsOneWidget);
    expect(find.text('user@example.invalid'), findsOneWidget);
    expect(find.textContaining('JBSWY3DPEHPK3PXP'), findsNothing);
    expect(find.textContaining('otpauth://'), findsNothing);
    expect(repository.addedAccount, isNull);
    expect(repository.importCallCount, 0);

    await tester.tap(find.byKey(TotpImportPreviewDialog.cancelButtonKey));
    await tester.pumpAndSettle();

    expect(repository.addedAccount, isNull);
    expect(repository.importCallCount, 0);
    expect(repository.importedAccounts, isEmpty);
  });

  testWidgets('standard otpauth confirm dùng atomic import và giữ semantics', (
    tester,
  ) async {
    final controller = _FakeScannerController();
    final repository = _MemoryAuthenticatorRepository();
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await _pumpPage(tester, accountsBloc, controller);
    await tester.tap(find.byTooltip('Quét mã QR'));
    await tester.pump();
    _scan(tester, _standardTotpUri);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(TotpImportPreviewDialog.confirmButtonKey));
    await tester.pumpAndSettle();

    expect(repository.addedAccount, isNull);
    expect(repository.importCallCount, 1);
    expect(
      repository.importedAccounts.single,
      const AuthenticatorAccount(
        id: '',
        issuer: 'TEST_ONLY Standard',
        accountName: 'user@example.invalid',
        secretKey: 'JBSWY3DPEHPK3PXP',
        algorithm: 'SHA256',
        digits: 8,
        period: 60,
      ),
    );
    expect(find.text('Đã nhập 1 mã.'), findsOneWidget);
  });

  testWidgets('hủy Google migration preview không mutate repository', (
    tester,
  ) async {
    final controller = _FakeScannerController();
    final repository = _MemoryAuthenticatorRepository();
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await _pumpPage(tester, accountsBloc, controller);
    await tester.tap(find.byTooltip('Quét mã QR'));
    await tester.pump();
    _scan(tester, _googleSingleBatchUri);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(TotpImportPreviewDialog.cancelButtonKey));
    await tester.pumpAndSettle();

    expect(repository.importCallCount, 0);
    expect(repository.importedAccounts, isEmpty);
    expect(find.byType(AddAccountPage), findsOneWidget);
  });

  testWidgets(
    'Google import preview không overflow và mặc định focus Hủy ở text scale 200%',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _FakeScannerController();
      final repository = _MemoryAuthenticatorRepository();
      final accountsBloc = _accountsBloc(repository);
      addTearDown(accountsBloc.close);

      await _pumpPage(
        tester,
        accountsBloc,
        controller,
        textScaler: const TextScaler.linear(2),
      );
      await tester.tap(find.byTooltip('Quét mã QR'));
      await tester.pump();
      _scan(tester, _googleSingleBatchUri);
      await tester.pumpAndSettle();

      final layoutException = tester.takeException();
      expect(
        layoutException is FlutterError
            ? layoutException.toStringDeep()
            : layoutException,
        isNull,
      );
      expectPrimaryFocusWithin(
        find.byKey(TotpImportPreviewDialog.cancelButtonKey),
      );
      final dialogSemantics = tester.getSemantics(find.byType(AlertDialog));
      expect(dialogSemantics.toStringDeep(), isNot(contains('KRCVGVC7')));
      expect(
        dialogSemantics.toStringDeep(),
        isNot(contains('TEST_ONLY_SECRET')),
      );
      semantics.dispose();
    },
  );

  testWidgets('Google multi-part hiển thị progress và import đúng thứ tự', (
    tester,
  ) async {
    final controller = _FakeScannerController();
    final repository = _MemoryAuthenticatorRepository();
    final accountsBloc = _accountsBloc(repository);
    addTearDown(accountsBloc.close);

    await _pumpPage(tester, accountsBloc, controller);
    await tester.tap(find.byTooltip('Quét mã QR'));
    await tester.pump();

    _scan(tester, _googleBatchPartOneUri);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(
      find.byKey(AddAccountPage.migrationBatchProgressKey),
      findsOneWidget,
    );
    expect(find.textContaining('đã quét 1/2'), findsOneWidget);
    expect(repository.importCallCount, 0);

    _scan(tester, _googleBatchPartZeroUri);
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra mã sẽ nhập'), findsOneWidget);
    await tester.tap(find.byKey(TotpImportPreviewDialog.confirmButtonKey));
    await tester.pumpAndSettle();

    expect(repository.importedAccounts.map((account) => account.accountName), [
      'alice@example.invalid',
      'bob@example.invalid',
    ]);
  });
}

void _scan(WidgetTester tester, String rawValue) {
  tester
      .widget<MobileScanner>(find.byType(MobileScanner))
      .onDetect!
      .call(BarcodeCapture(barcodes: <Barcode>[Barcode(rawValue: rawValue)]));
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
    importAccounts: ImportAccounts(repository),
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
  final List<AuthenticatorAccount> importedAccounts = [];
  int importCallCount = 0;

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
  Future<Either<Failure, AccountImportSummary>> importAccounts(
    List<AuthenticatorAccount> accounts,
  ) async {
    importCallCount++;
    importedAccounts
      ..clear()
      ..addAll(accounts);
    return Right(
      AccountImportSummary(importedCount: accounts.length, duplicateCount: 0),
    );
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
