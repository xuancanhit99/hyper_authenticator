import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Needed to update accounts after download
import 'package:hyper_authenticator/features/sync/domain/usecases/download_accounts_usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/get_last_sync_time_usecase.dart'; // Added
import 'package:hyper_authenticator/features/sync/domain/usecases/has_remote_data_usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/upload_accounts_usecase.dart';
import 'package:injectable/injectable.dart';

part 'sync_event.dart';
part 'sync_state.dart';

@injectable
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final HasRemoteDataUseCase _hasRemoteDataUseCase;
  final UploadAccountsUseCase _uploadAccountsUseCase;
  final DownloadAccountsUseCase _downloadAccountsUseCase;
  final GetLastSyncTimeUseCase _getLastSyncTimeUseCase; // Added
  final AccountsBloc _accountsBloc; // Inject AccountsBloc to update local data

  SyncBloc(
    this._hasRemoteDataUseCase,
    this._uploadAccountsUseCase,
    this._downloadAccountsUseCase,
    this._getLastSyncTimeUseCase, // Added
    this._accountsBloc, // Inject AccountsBloc
  ) : super(SyncInitial()) {
    on<CheckSyncStatus>(_onCheckSyncStatus);
    on<UploadAccountsRequested>(_onUploadAccountsRequested);
    on<DownloadAccountsRequested>(_onDownloadAccountsRequested);
  }

  Future<void> _onCheckSyncStatus(
    CheckSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    emit(SyncInProgress());
    final result = await _hasRemoteDataUseCase(NoParams());
    await result.fold(
      (failure) async => emit(SyncFailure(message: failure.message)),
      (hasData) async {
        // If remote data exists or not, also fetch the last sync time
        final timeResult = await _getLastSyncTimeUseCase(NoParams());
        final lastSyncTime = timeResult.getOrElse(
          (_) => null,
        ); // Get time or null on failure
        emit(
          SyncStatusChecked(hasRemoteData: hasData, lastSyncTime: lastSyncTime),
        );
      },
    );
  }

  Future<void> _onUploadAccountsRequested(
    UploadAccountsRequested event,
    Emitter<SyncState> emit,
  ) async {
    emit(SyncInProgress());
    final result = await _uploadAccountsUseCase(
      UploadAccountsParams(accounts: event.accountsToUpload),
    );
    result.fold(
      (failure) => emit(SyncFailure(message: failure.message)),
      (_) => emit(
        SyncSuccess(message: 'Accounts uploaded successfully.'),
      ), // Removed const
    );
    // Optionally re-check status after upload
    add(CheckSyncStatus());
  }

  Future<void> _onDownloadAccountsRequested(
    DownloadAccountsRequested event,
    Emitter<SyncState> emit,
  ) async {
    emit(SyncInProgress());
    final result = await _downloadAccountsUseCase(NoParams());
    result.fold((failure) => emit(SyncFailure(message: failure.message)), (
      downloadedAccounts,
    ) {
      // *** IMPORTANT: Need an event in AccountsBloc to handle this ***
      // For now, just emit success. Integration with AccountsBloc is next.
      _accountsBloc.add(
        ReplaceAccountsEvent(accounts: downloadedAccounts),
      ); // Assuming ReplaceAccountsEvent exists
      emit(
        SyncSuccess(message: 'Accounts downloaded successfully.'),
      ); // Removed const
      // Optionally re-check status after download
      add(CheckSyncStatus());
    });
  }
}

// TODO: Define ReplaceAccountsEvent in lib/features/authenticator/presentation/bloc/accounts_event.dart
// Example:
/*
class ReplaceAccountsEvent extends AccountsEvent {
  final List<AuthenticatorAccount> accounts;
  const ReplaceAccountsEvent({required this.accounts});
  @override List<Object> get props => [accounts];
}
*/

// TODO: Add handler for ReplaceAccountsEvent in lib/features/authenticator/presentation/bloc/accounts_bloc.dart
// Example:
/*
  Future<void> _onReplaceAccounts(
    ReplaceAccountsEvent event,
    Emitter<AccountsState> emit,
  ) async {
    emit(AccountsLoading()); // Or keep current state?
    // Consider clearing local storage first if this is a full replace
    await deleteAllAccounts(NoParams()); // Requires DeleteAllAccounts usecase
    for (final account in event.accounts) {
       // Use AddAccount usecase, handling potential errors
       await addAccount(AddAccountParams(account: account));
    }
     // Fetch accounts again to reflect changes
    add(LoadAccounts());
  }
*/
