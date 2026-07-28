import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/encrypted_backup_file_gateway.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/encrypted_backup_file_codec.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/encrypted_backup_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/pages/encrypted_backup_page.dart';

void main() {
  late EncryptedBackupFileCodec codec;

  setUp(() {
    codec = EncryptedBackupFileCodec.forTesting(
      memoryKiB: 32,
      iterations: 1,
      randomBytes: (int length) =>
          List<int>.generate(length, (index) => (length + index * 3) & 0xff),
      now: () => DateTime.utc(2026, 7, 27, 14),
    );
  });

  testWidgets(
    'restore yêu cầu password, preview không secret và typed confirmation',
    (tester) async {
      final existing = [_account(id: 'existing', issuer: 'Existing')];
      final replacement = [
        _account(id: 'restored', issuer: 'Restored Service'),
      ];
      final encrypted = await codec.encrypt(
        accounts: replacement,
        password: 'TEST_ONLY-password-1',
      );
      final repository = _MemoryRepository(existing);
      final gateway = _MemoryGateway(pickedBytes: encrypted);
      final backupBloc = EncryptedBackupBloc(repository, codec, gateway);
      final accountsBloc = _accountsBloc(repository);
      addTearDown(backupBloc.close);
      addTearDown(accountsBloc.close);

      await tester.pumpWidget(
        BlocProvider<AccountsBloc>.value(
          value: accountsBloc,
          child: MaterialApp(home: EncryptedBackupPage(bloc: backupBloc)),
        ),
      );

      await tester.tap(find.byKey(const Key('pick-encrypted-backup')));
      await tester.pumpAndSettle();
      expect(find.text('Mở file backup'), findsOneWidget);

      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(find.text('Mở file backup'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('backup-password')),
        'TEST_ONLY-password-1',
      );
      await tester.tap(find.byKey(const Key('submit-backup-password')));
      await tester.pumpAndSettle();

      expect(find.text('Restored Service'), findsOneWidget);
      expect(find.textContaining('1 tài khoản hiện tại → 1'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(Scaffold)).toString(),
        isNot(contains(replacement.first.secretKey)),
      );
      final restoreButton = find.byKey(const Key('confirm-atomic-restore'));
      expect(tester.widget<FilledButton>(restoreButton).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('restore-confirmation-phrase')),
        'KHOI PHUC',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(restoreButton).onPressed, isNotNull);
      await tester.tap(restoreButton);
      await tester.pumpAndSettle();

      expect(repository.replaceCalls, 1);
      expect(repository.accounts, replacement);
      expect(find.textContaining('Khôi phục hoàn tất'), findsOneWidget);
    },
  );

  testWidgets('export bắt password đủ dài và nhập lại chính xác', (
    tester,
  ) async {
    final repository = _MemoryRepository([
      _account(id: 'existing', issuer: 'Existing'),
    ]);
    final gateway = _MemoryGateway();
    final backupBloc = EncryptedBackupBloc(repository, codec, gateway);
    final accountsBloc = _accountsBloc(repository);
    addTearDown(backupBloc.close);
    addTearDown(accountsBloc.close);

    await tester.pumpWidget(
      BlocProvider<AccountsBloc>.value(
        value: accountsBloc,
        child: MaterialApp(home: EncryptedBackupPage(bloc: backupBloc)),
      ),
    );
    await tester.tap(find.byKey(const Key('create-encrypted-backup')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('backup-password')), 'short');
    await tester.enterText(
      find.byKey(const Key('backup-password-confirmation')),
      'different',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pump();

    expect(find.textContaining('ít nhất 12 ký tự'), findsOneWidget);
    expect(find.textContaining('không giống nhau'), findsOneWidget);
    expect(gateway.savedBytes, isNull);

    await tester.enterText(
      find.byKey(const Key('backup-password')),
      'TEST_ONLY-password-1',
    );
    await tester.enterText(
      find.byKey(const Key('backup-password-confirmation')),
      'TEST_ONLY-password-1',
    );
    await tester.tap(find.byKey(const Key('submit-backup-password')));
    await tester.pumpAndSettle();

    expect(gateway.savedBytes, isNotNull);
    expect(find.textContaining('Đã tạo file backup'), findsOneWidget);
  });

  testWidgets(
    'lifecycle rời foreground hủy preview và không thay local vault',
    (tester) async {
      final existing = [_account(id: 'existing', issuer: 'Existing')];
      final replacement = [
        _account(id: 'restored', issuer: 'Restored Service'),
      ];
      final encrypted = await codec.encrypt(
        accounts: replacement,
        password: 'TEST_ONLY-password-1',
      );
      final repository = _MemoryRepository(existing);
      final backupBloc = EncryptedBackupBloc(
        repository,
        codec,
        _MemoryGateway(pickedBytes: encrypted),
      );
      final accountsBloc = _accountsBloc(repository);
      addTearDown(backupBloc.close);
      addTearDown(accountsBloc.close);

      await tester.pumpWidget(
        BlocProvider<AccountsBloc>.value(
          value: accountsBloc,
          child: MaterialApp(home: EncryptedBackupPage(bloc: backupBloc)),
        ),
      );
      await tester.tap(find.byKey(const Key('pick-encrypted-backup')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('backup-password')),
        'TEST_ONLY-password-1',
      );
      await tester.tap(find.byKey(const Key('submit-backup-password')));
      await tester.pumpAndSettle();
      expect(find.text('Restored Service'), findsOneWidget);

      final cancellation = backupBloc.stream.firstWhere(
        (state) => state is EncryptedBackupCancelled,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final cancelledState = await cancellation as EncryptedBackupCancelled;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Restored Service'), findsNothing);
      expect(cancelledState.message, contains('không còn ở foreground'));
      expect(repository.replaceCalls, 0);
      expect(repository.accounts, existing);
    },
  );

  testWidgets(
    'file picker trả kết quả khi paused chỉ mở password sau resumed',
    (tester) async {
      final encrypted = await codec.encrypt(
        accounts: [_account(id: 'restored', issuer: 'Restored Service')],
        password: 'TEST_ONLY-password-1',
      );
      final repository = _MemoryRepository(const []);
      final gateway = _DeferredPickGateway();
      final backupBloc = EncryptedBackupBloc(repository, codec, gateway);
      final accountsBloc = _accountsBloc(repository);
      addTearDown(backupBloc.close);
      addTearDown(accountsBloc.close);

      await tester.pumpWidget(
        BlocProvider<AccountsBloc>.value(
          value: accountsBloc,
          child: MaterialApp(home: EncryptedBackupPage(bloc: backupBloc)),
        ),
      );
      await tester.tap(find.byKey(const Key('pick-encrypted-backup')));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gateway.complete(encrypted);
      await tester.pump();
      expect(find.text('Mở file backup'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Mở file backup'), findsOneWidget);
    },
  );

  testWidgets('layout không overflow ở viewport 320 và text scale 200%', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final repository = _MemoryRepository(const []);
    final backupBloc = EncryptedBackupBloc(repository, codec, _MemoryGateway());
    final accountsBloc = _accountsBloc(repository);
    addTearDown(backupBloc.close);
    addTearDown(accountsBloc.close);

    await tester.pumpWidget(
      BlocProvider<AccountsBloc>.value(
        value: accountsBloc,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: EncryptedBackupPage(bloc: backupBloc),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Backup file mã hóa'), findsOneWidget);
  });
}

AccountsBloc _accountsBloc(AuthenticatorRepository repository) => AccountsBloc(
  getAccounts: GetAccounts(repository),
  addAccount: AddAccount(repository),
  deleteAccount: DeleteAccount(repository),
  updateAccount: UpdateAccount(repository),
  importAccounts: ImportAccounts(repository),
);

AuthenticatorAccount _account({required String id, required String issuer}) =>
    AuthenticatorAccount(
      id: id,
      issuer: issuer,
      accountName: '$id@example.invalid',
      secretKey: 'JBSWY3DPEHPK3PXP',
      algorithm: 'SHA256',
      digits: 7,
      period: 60,
    );

class _MemoryGateway implements EncryptedBackupFileGateway {
  _MemoryGateway({Uint8List? pickedBytes})
    : pickedBytes = pickedBytes == null
          ? null
          : Uint8List.fromList(pickedBytes);

  final Uint8List? pickedBytes;
  Uint8List? savedBytes;

  @override
  Future<EncryptedBackupFileSelection?> pickBackup() async =>
      pickedBytes == null
      ? null
      : EncryptedBackupFileSelection(
          bytes: pickedBytes!,
          displayName: 'test.hyauth',
        );

  @override
  Future<BackupFileSaveResult> saveBackup({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    savedBytes = Uint8List.fromList(bytes);
    return BackupFileSaveResult.saved;
  }
}

class _DeferredPickGateway implements EncryptedBackupFileGateway {
  final _selection = Completer<EncryptedBackupFileSelection?>();

  void complete(Uint8List bytes) {
    _selection.complete(
      EncryptedBackupFileSelection(
        bytes: Uint8List.fromList(bytes),
        displayName: 'test.hyauth',
      ),
    );
  }

  @override
  Future<EncryptedBackupFileSelection?> pickBackup() => _selection.future;

  @override
  Future<BackupFileSaveResult> saveBackup({
    required Uint8List bytes,
    required String suggestedName,
  }) => throw UnimplementedError();
}

class _MemoryRepository implements AuthenticatorRepository {
  _MemoryRepository(List<AuthenticatorAccount> accounts)
    : accounts = List<AuthenticatorAccount>.from(accounts);

  final List<AuthenticatorAccount> accounts;
  int replaceCalls = 0;

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List<AuthenticatorAccount>.unmodifiable(accounts));

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> replacement,
  ) async {
    replaceCalls++;
    accounts
      ..clear()
      ..addAll(replacement);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, AuthenticatorAccount>> addAccount({
    required String issuer,
    required String accountName,
    required String secretKey,
    required String algorithm,
    required int digits,
    required int period,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> deleteAccount(String id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, AccountImportSummary>> importAccounts(
    List<AuthenticatorAccount> accounts,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, AuthenticatorAccount>> saveAccount(
    AuthenticatorAccount account,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAccount(AuthenticatorAccount account) =>
      throw UnimplementedError();
}
