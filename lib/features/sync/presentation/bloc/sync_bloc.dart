import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/encrypted_vault_sync_usecase.dart';
import 'package:injectable/injectable.dart';

part 'sync_event.dart';
part 'sync_state.dart';

@injectable
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final EncryptedVaultSyncUseCase _sync;
  final AccountsBloc _accountsBloc;

  SyncBloc(this._sync, this._accountsBloc) : super(const SyncInitial()) {
    on<CheckSyncStatus>(_onCheckStatus);
    on<BeginEncryptedSyncSetup>(_onBeginSetup);
    on<ConfirmRecoveryKeySaved>(_onConfirmSetup);
    on<RecoverEncryptedSync>(_onRecover);
    on<SetEncryptedSyncEnabled>(_onSetEnabled);
    on<SyncNowRequested>(_onSyncNow);
    on<ResolveSyncConflictWithCloud>(_onUseCloud);
    on<ResolveSyncConflictWithLocal>(_onKeepLocal);
    on<CancelSensitiveSyncOperation>(_onCancelSensitiveOperation);
  }

  Future<void> _onCheckStatus(
    CheckSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang kiểm tra encrypted vault...'));
    await _emitResult(await _sync.inspect(), emit);
  }

  Future<void> _onBeginSetup(
    BeginEncryptedSyncSetup event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang tạo vault key...'));
    await _emitResult(await _sync.prepareSetup(), emit);
  }

  Future<void> _onConfirmSetup(
    ConfirmRecoveryKeySaved event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang publish encrypted snapshot đầu tiên...'));
    await _emitResult(await _sync.confirmSetup(), emit);
  }

  Future<void> _onRecover(
    RecoverEncryptedSync event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang xác thực recovery key...'));
    await _emitResult(await _sync.recover(event.recoveryCode), emit);
  }

  Future<void> _onSetEnabled(
    SetEncryptedSyncEnabled event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang cập nhật trạng thái sync...'));
    await _emitResult(await _sync.setEnabled(event.enabled), emit);
  }

  Future<void> _onSyncNow(
    SyncNowRequested event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang đồng bộ encrypted snapshot...'));
    await _emitResult(await _sync.sync(), emit);
  }

  Future<void> _onUseCloud(
    ResolveSyncConflictWithCloud event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang khôi phục snapshot từ cloud...'));
    await _emitResult(await _sync.useCloud(), emit);
  }

  Future<void> _onKeepLocal(
    ResolveSyncConflictWithLocal event,
    Emitter<SyncState> emit,
  ) async {
    if (!_supported(emit)) return;
    emit(const SyncInProgress('Đang publish snapshot local đã xác nhận...'));
    await _emitResult(await _sync.keepLocal(), emit);
  }

  void _onCancelSensitiveOperation(
    CancelSensitiveSyncOperation event,
    Emitter<SyncState> emit,
  ) {
    _sync.cancelSensitiveOperation();
    emit(const SyncInitial());
    add(const CheckSyncStatus());
  }

  Future<void> _emitResult(
    Either<Failure, EncryptedSyncResult> either,
    Emitter<SyncState> emit,
  ) async {
    await either.fold(
      (Failure failure) async => emit(
        SyncFailure(
          failure.message,
          isConflict: failure is SyncRevisionConflictFailure,
        ),
      ),
      (EncryptedSyncResult result) async {
        switch (result) {
          case EncryptedSyncSetupRequired():
            emit(const SyncSetupRequired());
          case EncryptedSyncRecoveryRequired(:final updatedAt):
            emit(SyncRecoveryRequired(updatedAt));
          case EncryptedSyncRecoveryKeyReady(:final recoveryCode):
            emit(SyncRecoveryKeyReady(recoveryCode));
          case EncryptedSyncReady(
            :final isEnabled,
            :final revision,
            :final updatedAt,
          ):
            emit(
              SyncReady(
                isEnabled: isEnabled,
                revision: revision,
                updatedAt: updatedAt,
              ),
            );
          case EncryptedSyncConflict(
            :final remoteRevision,
            :final remoteUpdatedAt,
          ):
            emit(
              SyncConflict(
                remoteRevision: remoteRevision,
                remoteUpdatedAt: remoteUpdatedAt,
              ),
            );
          case EncryptedSyncCompleted(:final revision, :final completedAt):
            _accountsBloc.add(LoadAccounts());
            emit(SyncSuccess(revision: revision, completedAt: completedAt));
        }
      },
    );
  }

  bool _supported(Emitter<SyncState> emit) {
    if (PlatformCapabilities.supportsEncryptedCloudSync) return true;
    emit(
      const SyncUnavailable(
        'Encrypted cloud sync chưa hỗ trợ Web vì browser key storage có trust boundary khác native.',
      ),
    );
    return false;
  }
}
