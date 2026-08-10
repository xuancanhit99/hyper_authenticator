import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/error/user_facing_failure.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_signal.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_signal_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/synchronize_accounts.dart';
import 'package:injectable/injectable.dart';

part 'sync_event.dart';
part 'sync_state.dart';

/// Owner duy nhất của trạng thái account-managed cloud sync.
///
/// BLoC nghe auth lifecycle và mutation local để đồng bộ tự động; Settings chỉ
/// render status và phát retry event.
@lazySingleton
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  SyncBloc(this._sync, this._signals, this._authBloc, this._accountsBloc)
    : super(const SyncInitial()) {
    on<CheckSyncStatus>(_onSyncRequested);
    on<SyncNowRequested>(_onSyncRequested);
    on<_AuthSyncRequested>(_onAuthChanged);
    on<_LocalMutationSyncRequested>(_onSyncRequested);
    on<_RealtimeSyncRequested>(_onRealtimeSyncRequested);

    _authSubscription = _authBloc.stream.listen((state) {
      add(
        _AuthSyncRequested(state is AuthAuthenticated ? state.user.id : null),
      );
    });
    _accountsSubscription = _accountsBloc.stream.listen((state) {
      if (state is AccountAddSuccess ||
          state is AccountImportSuccess ||
          state is AccountUpdateSuccess ||
          state is AccountDeleteSuccess) {
        add(const _LocalMutationSyncRequested());
      }
    });

    final currentAuthState = _authBloc.state;
    add(
      _AuthSyncRequested(
        currentAuthState is AuthAuthenticated ? currentAuthState.user.id : null,
      ),
    );
  }

  final AccountSynchronizer _sync;
  final AccountSyncSignalRepository _signals;
  final AuthBloc _authBloc;
  final AccountsBloc _accountsBloc;
  static const _realtimeDebounceDuration = Duration(milliseconds: 350);
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<AccountsState>? _accountsSubscription;
  StreamSubscription<AccountSyncSignal>? _realtimeSubscription;
  Timer? _realtimeDebounce;
  String? _realtimeUserId;

  @override
  Future<void> close() async {
    _realtimeDebounce?.cancel();
    await _realtimeSubscription?.cancel();
    await _authSubscription?.cancel();
    await _accountsSubscription?.cancel();
    return super.close();
  }

  Future<void> _onAuthChanged(
    _AuthSyncRequested event,
    Emitter<SyncState> emit,
  ) async {
    await _replaceRealtimeSubscription(event.userId);
    if (event.userId == null) {
      emit(const SyncSignedOut());
      return;
    }
    await _runSync(emit);
  }

  Future<void> _replaceRealtimeSubscription(String? userId) async {
    if (_realtimeUserId == userId && _realtimeSubscription != null) return;
    _realtimeDebounce?.cancel();
    _realtimeDebounce = null;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _realtimeUserId = userId;
    if (userId == null) return;

    _realtimeSubscription = _signals
        .watch(userId: userId)
        .listen(
          (_) => _scheduleRealtimeSync(userId),
          onError: (_, _) {
            // Realtime là best-effort wake-up. RPC sync/resume/refresh/retry
            // tiếp tục hoạt động và không bị đổi thành failure state.
          },
        );
  }

  void _scheduleRealtimeSync(String userId) {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(_realtimeDebounceDuration, () {
      if (!isClosed && _realtimeUserId == userId) {
        add(_RealtimeSyncRequested(userId));
      }
    });
  }

  Future<void> _onRealtimeSyncRequested(
    _RealtimeSyncRequested event,
    Emitter<SyncState> emit,
  ) async {
    final authState = _authBloc.state;
    if (_realtimeUserId != event.userId ||
        authState is! AuthAuthenticated ||
        authState.user.id != event.userId) {
      return;
    }
    await _runSync(emit);
  }

  Future<void> _onSyncRequested(SyncEvent event, Emitter<SyncState> emit) =>
      _runSync(emit);

  Future<void> _runSync(Emitter<SyncState> emit) async {
    emit(const SyncInProgress());
    await _emitResult(await _sync(), emit);
  }

  Future<void> _emitResult(
    Either<Failure, AccountSyncResult> either,
    Emitter<SyncState> emit,
  ) async {
    await either.fold(
      (failure) async => emit(
        SyncFailure(
          userFacingFailureMessage(failure, context: UserFailureContext.sync),
        ),
      ),
      (result) async {
        switch (result) {
          case AccountSyncSignedOut():
            emit(const SyncSignedOut());
          case AccountSyncCompleted(
            :final completedAt,
            :final uploadedCount,
            :final downloadedCount,
            :final deletedCount,
          ):
            if (downloadedCount > 0 || deletedCount > 0) {
              _accountsBloc.add(LoadAccounts());
            }
            emit(
              SyncReady(
                completedAt: completedAt,
                uploadedCount: uploadedCount,
                downloadedCount: downloadedCount,
                deletedCount: deletedCount,
              ),
            );
        }
      },
    );
  }
}
