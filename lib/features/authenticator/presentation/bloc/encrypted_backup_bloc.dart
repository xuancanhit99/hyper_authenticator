import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/encrypted_backup_file_gateway.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/encrypted_backup_file_codec.dart';
import 'package:injectable/injectable.dart';
import 'package:intl/intl.dart';

part 'encrypted_backup_event.dart';
part 'encrypted_backup_state.dart';

@injectable
class EncryptedBackupBloc
    extends Bloc<EncryptedBackupEvent, EncryptedBackupState> {
  EncryptedBackupBloc(this._repository, this._codec, this._fileGateway)
    : _previewLifetime = const Duration(minutes: 2),
      super(const EncryptedBackupInitial()) {
    _registerHandlers();
  }

  EncryptedBackupBloc.forTesting(
    this._repository,
    this._codec,
    this._fileGateway, {
    required this._previewLifetime,
  }) : super(const EncryptedBackupInitial()) {
    _registerHandlers();
  }

  void _registerHandlers() {
    on<CreateEncryptedBackupRequested>(_onCreate);
    on<PickEncryptedBackupRequested>(_onPick);
    on<DecryptEncryptedBackupRequested>(_onDecrypt);
    on<ConfirmEncryptedBackupRestore>(_onConfirmRestore);
    on<DiscardEncryptedBackup>(_onDiscard);
    on<EncryptedBackupPreviewExpired>(_onExpired);
  }

  final AuthenticatorRepository _repository;
  final EncryptedBackupFileCodec _codec;
  final EncryptedBackupFileGateway _fileGateway;
  final Duration _previewLifetime;

  Uint8List? _pendingEncryptedBytes;
  List<AuthenticatorAccount>? _pendingRestoreAccounts;
  Timer? _previewTimer;
  int _previewGeneration = 0;
  bool _isClosing = false;

  Future<void> _onCreate(
    CreateEncryptedBackupRequested event,
    Emitter<EncryptedBackupState> emit,
  ) async {
    _clearPending();
    emit(const EncryptedBackupBusy('Đang mã hóa snapshot local…'));
    Uint8List? encoded;
    try {
      final accountsResult = await _repository.getAccounts();
      if (_cannotContinue(emit)) return;
      final accounts = accountsResult.fold<List<AuthenticatorAccount>>(
        (failure) => throw _RepositoryBackupException(failure),
        (value) => value,
      );
      encoded = await _codec.encrypt(
        accounts: accounts,
        password: event.password,
      );
      if (_cannotContinue(emit)) return;
      emit(const EncryptedBackupBusy('Đang mở vị trí lưu an toàn…'));
      final result = await _fileGateway.saveBackup(
        bytes: encoded,
        suggestedName: _suggestedFileName(),
      );
      if (_cannotContinue(emit)) return;
      emit(switch (result) {
        BackupFileSaveResult.saved => EncryptedBackupSuccess(
          message:
              'Đã tạo file backup mã hóa. Hãy giữ file và password ở hai nơi an toàn khác nhau.',
          restored: false,
        ),
        BackupFileSaveResult.cancelled => const EncryptedBackupCancelled(
          'Bạn đã hủy vị trí lưu; vault không thay đổi.',
        ),
      });
    } on BackupFileException catch (error) {
      if (_cannotContinue(emit)) return;
      emit(EncryptedBackupFailure(error.message));
    } on BackupFileIoException catch (error) {
      if (_cannotContinue(emit)) return;
      emit(EncryptedBackupFailure(error.message));
    } on _RepositoryBackupException {
      if (_cannotContinue(emit)) return;
      emit(
        const EncryptedBackupFailure(
          'Không thể đọc local vault để tạo backup.',
        ),
      );
    } catch (_) {
      if (_cannotContinue(emit)) return;
      emit(
        const EncryptedBackupFailure(
          'Không thể tạo file backup; vault không thay đổi.',
        ),
      );
    } finally {
      encoded?.fillRange(0, encoded.length, 0);
    }
  }

  Future<void> _onPick(
    PickEncryptedBackupRequested event,
    Emitter<EncryptedBackupState> emit,
  ) async {
    _clearPending();
    emit(const EncryptedBackupBusy('Đang mở system file picker…'));
    try {
      final selection = await _fileGateway.pickBackup();
      if (_cannotContinue(emit)) {
        selection?.bytes.fillRange(0, selection.bytes.length, 0);
        return;
      }
      if (selection == null) {
        emit(
          const EncryptedBackupCancelled(
            'Bạn đã hủy chọn file; vault không thay đổi.',
          ),
        );
        return;
      }
      _pendingEncryptedBytes = selection.bytes;
      emit(const EncryptedBackupPasswordRequired());
    } on BackupFileIoException catch (error) {
      if (_cannotContinue(emit)) return;
      emit(EncryptedBackupFailure(error.message));
    } catch (_) {
      if (_cannotContinue(emit)) return;
      emit(
        const EncryptedBackupFailure(
          'Không thể đọc file backup; vault không thay đổi.',
        ),
      );
    }
  }

  Future<void> _onDecrypt(
    DecryptEncryptedBackupRequested event,
    Emitter<EncryptedBackupState> emit,
  ) async {
    final encryptedBytes = _pendingEncryptedBytes;
    if (encryptedBytes == null) {
      emit(
        const EncryptedBackupFailure(
          'Phiên import đã hết hạn. Hãy chọn lại file backup.',
        ),
      );
      return;
    }
    emit(const EncryptedBackupBusy('Đang xác thực và giải mã file…'));
    try {
      final snapshot = await _codec.decrypt(
        fileBytes: encryptedBytes,
        password: event.password,
      );
      if (_cannotContinue(emit)) return;
      final currentResult = await _repository.getAccounts();
      if (_cannotContinue(emit)) return;
      final currentAccounts = currentResult.fold<List<AuthenticatorAccount>>(
        (failure) => throw _RepositoryBackupException(failure),
        (value) => value,
      );
      encryptedBytes.fillRange(0, encryptedBytes.length, 0);
      _pendingEncryptedBytes = null;
      _pendingRestoreAccounts = List<AuthenticatorAccount>.unmodifiable(
        snapshot.accounts,
      );
      final token = 'backup-preview-${++_previewGeneration}';
      final expiresAt = DateTime.now().toUtc().add(_previewLifetime);
      _previewTimer?.cancel();
      _previewTimer = Timer(
        _previewLifetime,
        () => add(EncryptedBackupPreviewExpired(token)),
      );
      emit(
        EncryptedBackupRestorePreview(
          token: token,
          createdAt: snapshot.createdAt,
          currentAccountCount: currentAccounts.length,
          accounts: snapshot.accounts
              .map(EncryptedBackupAccountPreview.fromAccount)
              .toList(growable: false),
          expiresAt: expiresAt,
        ),
      );
    } on BackupFileException catch (error) {
      _clearPending();
      if (_cannotContinue(emit)) return;
      emit(EncryptedBackupFailure(error.message));
    } on _RepositoryBackupException {
      _clearPending();
      if (_cannotContinue(emit)) return;
      emit(
        const EncryptedBackupFailure(
          'Không thể đọc local vault hiện tại; restore chưa bắt đầu.',
        ),
      );
    } catch (_) {
      _clearPending();
      if (_cannotContinue(emit)) return;
      emit(
        const EncryptedBackupFailure(
          'Không thể xác minh file backup; vault không thay đổi.',
        ),
      );
    }
  }

  Future<void> _onConfirmRestore(
    ConfirmEncryptedBackupRestore event,
    Emitter<EncryptedBackupState> emit,
  ) async {
    final currentState = state;
    final accounts = _pendingRestoreAccounts;
    if (currentState is! EncryptedBackupRestorePreview ||
        currentState.token != event.token ||
        accounts == null) {
      _clearPending();
      emit(
        const EncryptedBackupFailure(
          'Preview đã hết hạn. Hãy chọn và xác minh lại file backup.',
        ),
      );
      return;
    }
    _previewTimer?.cancel();
    emit(
      const EncryptedBackupBusy(
        'Đang publish snapshot mới bằng atomic local-vault commit…',
      ),
    );
    final result = await _repository.replaceAccounts(accounts);
    _clearPending();
    if (_cannotContinue(emit)) return;
    result.fold(
      (failure) => emit(
        EncryptedBackupFailure(
          '${failure.message} Snapshot active trước restore được giữ nguyên.',
        ),
      ),
      (_) => emit(
        EncryptedBackupSuccess(
          message:
              'Khôi phục hoàn tất. ${accounts.length} tài khoản đang active trong local vault.',
          restored: true,
        ),
      ),
    );
  }

  void _onDiscard(
    DiscardEncryptedBackup event,
    Emitter<EncryptedBackupState> emit,
  ) {
    _clearPending();
    emit(
      EncryptedBackupCancelled(
        event.reason ?? 'Đã hủy import; vault không thay đổi.',
      ),
    );
  }

  void _onExpired(
    EncryptedBackupPreviewExpired event,
    Emitter<EncryptedBackupState> emit,
  ) {
    final currentState = state;
    if (currentState is EncryptedBackupRestorePreview &&
        currentState.token == event.token) {
      _clearPending();
      emit(
        const EncryptedBackupCancelled(
          'Preview đã hết hạn; decrypted snapshot đã được loại khỏi phiên.',
        ),
      );
    }
  }

  void _clearPending() {
    _previewTimer?.cancel();
    _previewTimer = null;
    _pendingEncryptedBytes?.fillRange(0, _pendingEncryptedBytes!.length, 0);
    _pendingEncryptedBytes = null;
    _pendingRestoreAccounts = null;
  }

  bool _cannotContinue(Emitter<EncryptedBackupState> emit) =>
      _isClosing || emit.isDone;

  String _suggestedFileName() {
    final timestamp = DateFormat(
      "yyyyMMdd'T'HHmmss'Z'",
    ).format(DateTime.now().toUtc());
    return 'hyper-authenticator-$timestamp.${EncryptedBackupFileCodec.fileExtension}';
  }

  @override
  Future<void> close() {
    _isClosing = true;
    _clearPending();
    return super.close();
  }
}

class _RepositoryBackupException implements Exception {
  const _RepositoryBackupException(this.failure);

  final Failure failure;
}
