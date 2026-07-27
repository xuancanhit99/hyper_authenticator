import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/account_import_summary.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/encrypted_backup_file_gateway.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/encrypted_backup_file_codec.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/encrypted_backup_bloc.dart';

void main() {
  late EncryptedBackupFileCodec codec;

  setUp(() {
    codec = EncryptedBackupFileCodec.forTesting(
      memoryKiB: 32,
      iterations: 1,
      randomBytes: (int length) =>
          List<int>.generate(length, (index) => (index + length) & 0xff),
      now: () => DateTime.utc(2026, 7, 27, 12),
    );
  });

  test('wrong password fail closed và không gọi replacement', () async {
    final existing = [_account(id: 'existing', issuer: 'Existing')];
    final replacement = [_account(id: 'replacement', issuer: 'Replacement')];
    final encrypted = await codec.encrypt(
      accounts: replacement,
      password: 'TEST_ONLY-password-1',
    );
    final repository = _MemoryRepository(existing);
    final gateway = _MemoryGateway(pickedBytes: encrypted);
    final bloc = EncryptedBackupBloc(repository, codec, gateway);
    addTearDown(bloc.close);

    bloc.add(const PickEncryptedBackupRequested());
    await _state<EncryptedBackupPasswordRequired>(bloc);
    bloc.add(const DecryptEncryptedBackupRequested('TEST_ONLY-password-2'));
    final failure = await _state<EncryptedBackupFailure>(bloc);

    expect(failure.message, contains('Sai mật khẩu'));
    expect(repository.replaceCalls, 0);
    expect(repository.accounts, existing);
    expect(
      const DecryptEncryptedBackupRequested('TEST_ONLY-password-2').toString(),
      isNot(contains('TEST_ONLY-password-2')),
    );
  });

  test(
    'preview metadata rồi confirm gọi đúng một atomic replacement',
    () async {
      final existing = [_account(id: 'existing', issuer: 'Existing')];
      final replacement = [
        _account(id: 'one', issuer: 'Service One'),
        _account(id: 'two', issuer: 'Service Two'),
      ];
      final encrypted = await codec.encrypt(
        accounts: replacement,
        password: 'TEST_ONLY-password-1',
      );
      final repository = _MemoryRepository(existing);
      final bloc = EncryptedBackupBloc(
        repository,
        codec,
        _MemoryGateway(pickedBytes: encrypted),
      );
      addTearDown(bloc.close);

      bloc.add(const PickEncryptedBackupRequested());
      await _state<EncryptedBackupPasswordRequired>(bloc);
      bloc.add(const DecryptEncryptedBackupRequested('TEST_ONLY-password-1'));
      final preview = await _state<EncryptedBackupRestorePreview>(bloc);

      expect(preview.currentAccountCount, 1);
      expect(preview.accounts, hasLength(2));
      expect(preview.accounts.first.issuer, 'Service One');
      expect(preview.toString(), isNot(contains(replacement.first.secretKey)));

      bloc.add(ConfirmEncryptedBackupRestore(preview.token));
      final success = await _state<EncryptedBackupSuccess>(bloc);

      expect(success.restored, isTrue);
      expect(repository.replaceCalls, 1);
      expect(repository.accounts, replacement);
    },
  );

  test('cancel và preview timeout không mutate vault', () async {
    final existing = [_account(id: 'existing', issuer: 'Existing')];
    final replacement = [_account(id: 'replacement', issuer: 'Replacement')];
    final encrypted = await codec.encrypt(
      accounts: replacement,
      password: 'TEST_ONLY-password-1',
    );
    final repository = _MemoryRepository(existing);
    final bloc = EncryptedBackupBloc.forTesting(
      repository,
      codec,
      _MemoryGateway(pickedBytes: encrypted),
      previewLifetime: const Duration(milliseconds: 10),
    );
    addTearDown(bloc.close);

    bloc.add(const PickEncryptedBackupRequested());
    await _state<EncryptedBackupPasswordRequired>(bloc);
    bloc.add(const DecryptEncryptedBackupRequested('TEST_ONLY-password-1'));
    await _state<EncryptedBackupRestorePreview>(bloc);
    final cancelled = await _state<EncryptedBackupCancelled>(bloc);

    expect(cancelled.message, contains('hết hạn'));
    expect(repository.replaceCalls, 0);
    expect(repository.accounts, existing);
  });

  test('export chỉ đưa encrypted bytes cho file gateway', () async {
    final accounts = [_account(id: 'existing', issuer: 'Existing')];
    final repository = _MemoryRepository(accounts);
    final gateway = _MemoryGateway();
    final bloc = EncryptedBackupBloc(repository, codec, gateway);
    addTearDown(bloc.close);

    const event = CreateEncryptedBackupRequested('TEST_ONLY-password-1');
    expect(event.toString(), isNot(contains('TEST_ONLY-password-1')));
    bloc.add(event);
    final success = await _state<EncryptedBackupSuccess>(bloc);

    expect(success.restored, isFalse);
    expect(gateway.savedBytes, isNotNull);
    expect(
      String.fromCharCodes(gateway.savedBytes!),
      isNot(contains(accounts.first.secretKey)),
    );
    final decoded = await codec.decrypt(
      fileBytes: gateway.savedBytes!,
      password: 'TEST_ONLY-password-1',
    );
    expect(decoded.accounts, accounts);
  });

  test('hủy system save không mutate vault và trả trạng thái cancel', () async {
    final accounts = [_account(id: 'existing', issuer: 'Existing')];
    final repository = _MemoryRepository(accounts);
    final bloc = EncryptedBackupBloc(
      repository,
      codec,
      _MemoryGateway(saveResult: BackupFileSaveResult.cancelled),
    );
    addTearDown(bloc.close);

    bloc.add(const CreateEncryptedBackupRequested('TEST_ONLY-password-1'));
    final cancelled = await _state<EncryptedBackupCancelled>(bloc);

    expect(cancelled.message, contains('hủy vị trí lưu'));
    expect(repository.replaceCalls, 0);
    expect(repository.accounts, accounts);
  });

  test('close trong lúc system picker chờ không nhận file muộn', () async {
    final repository = _MemoryRepository([
      _account(id: 'existing', issuer: 'Existing'),
    ]);
    final gateway = _CompletingPickGateway();
    final bloc = EncryptedBackupBloc(repository, codec, gateway);

    bloc.add(const PickEncryptedBackupRequested());
    await _state<EncryptedBackupBusy>(bloc);
    final closeFuture = bloc.close();
    final selection = EncryptedBackupFileSelection(
      bytes: Uint8List.fromList([1, 2, 3]),
      displayName: 'late.hyauth',
    );
    gateway.complete(selection);

    await closeFuture;
    expect(selection.bytes, everyElement(0));
    expect(repository.replaceCalls, 0);
  });

  test(
    'replacement failure giữ vault hiện tại và không cho retry stale',
    () async {
      final existing = [_account(id: 'existing', issuer: 'Existing')];
      final replacement = [_account(id: 'replacement', issuer: 'Replacement')];
      final encrypted = await codec.encrypt(
        accounts: replacement,
        password: 'TEST_ONLY-password-1',
      );
      final repository = _MemoryRepository(existing)
        ..replacementFailure = const StorageFailure('Injected commit failure.');
      final bloc = EncryptedBackupBloc(
        repository,
        codec,
        _MemoryGateway(pickedBytes: encrypted),
      );
      addTearDown(bloc.close);

      bloc.add(const PickEncryptedBackupRequested());
      await _state<EncryptedBackupPasswordRequired>(bloc);
      bloc.add(const DecryptEncryptedBackupRequested('TEST_ONLY-password-1'));
      final preview = await _state<EncryptedBackupRestorePreview>(bloc);
      bloc.add(ConfirmEncryptedBackupRestore(preview.token));
      final failure = await _state<EncryptedBackupFailure>(bloc);

      expect(failure.message, contains('Snapshot active'));
      expect(repository.replaceCalls, 1);
      expect(repository.accounts, existing);

      bloc.add(ConfirmEncryptedBackupRestore(preview.token));
      await _state<EncryptedBackupFailure>(bloc);
      expect(repository.replaceCalls, 1);
    },
  );
}

Future<T> _state<T extends EncryptedBackupState>(
  EncryptedBackupBloc bloc,
) async {
  if (bloc.state case final T state) return state;
  return await bloc.stream.firstWhere((state) => state is T) as T;
}

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
  _MemoryGateway({
    Uint8List? pickedBytes,
    this.saveResult = BackupFileSaveResult.saved,
  }) : pickedBytes = pickedBytes == null
           ? null
           : Uint8List.fromList(pickedBytes);

  final Uint8List? pickedBytes;
  final BackupFileSaveResult saveResult;
  Uint8List? savedBytes;

  @override
  Future<EncryptedBackupFileSelection?> pickBackup() async =>
      pickedBytes == null
      ? null
      : EncryptedBackupFileSelection(
          bytes: pickedBytes!,
          displayName: 'test-backup.hyauth',
        );

  @override
  Future<BackupFileSaveResult> saveBackup({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    savedBytes = Uint8List.fromList(bytes);
    return saveResult;
  }
}

class _CompletingPickGateway implements EncryptedBackupFileGateway {
  final _completer = Completer<EncryptedBackupFileSelection?>();

  void complete(EncryptedBackupFileSelection selection) {
    _completer.complete(selection);
  }

  @override
  Future<EncryptedBackupFileSelection?> pickBackup() => _completer.future;

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
  Failure? replacementFailure;
  int replaceCalls = 0;

  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      Right(List<AuthenticatorAccount>.unmodifiable(accounts));

  @override
  Future<Either<Failure, Unit>> replaceAccounts(
    List<AuthenticatorAccount> replacement,
  ) async {
    replaceCalls++;
    final failure = replacementFailure;
    if (failure != null) return Left(failure);
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
