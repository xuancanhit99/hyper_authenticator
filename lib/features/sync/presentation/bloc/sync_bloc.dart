import 'dart:async'; // Import async library for Completer and StreamSubscription

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Needed to update accounts after download
import 'package:hyper_authenticator/features/sync/domain/usecases/download_accounts_usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/get_last_sync_time_usecase.dart'; // Use case class renamed to GetLastSyncTimeUseCase
import 'package:hyper_authenticator/features/sync/domain/usecases/has_remote_data_usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/upload_accounts_usecase.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences

part 'sync_event.dart';
part 'sync_state.dart';

@injectable
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final HasRemoteDataUseCase _hasRemoteDataUseCase;
  final UploadAccountsUseCase _uploadAccountsUseCase;
  final DownloadAccountsUseCase _downloadAccountsUseCase;
  final GetLastSyncTimeUseCase // Use renamed class
  _getLastSyncTimeUseCase; // Rename field for consistency
  final AccountsBloc _accountsBloc;
  final SharedPreferences _prefs; // Add SharedPreferences dependency

  // --- State for Sync Enabled ---
  // TODO: Persist this state using SharedPreferences or similar
  bool _isSyncEnabled = false;

  // --- Bloc-to-Bloc Communication ---
  StreamSubscription<AccountsState>? _accountsSubscription;
  Completer<List<AuthenticatorAccount>>? _mergeCompleter;

  static const String _syncEnabledPrefKey =
      'sync_enabled'; // Define key for preference

  SyncBloc(
    this._hasRemoteDataUseCase,
    this._uploadAccountsUseCase,
    this._downloadAccountsUseCase,
    this._getLastSyncTimeUseCase, // Use renamed parameter
    this._accountsBloc,
    this._prefs, // Inject SharedPreferences
  ) : super(SyncInitial()) {
    // Load initial sync enabled state
    _isSyncEnabled = _prefs.getBool(_syncEnabledPrefKey) ?? false;
    print("[SyncBloc] Initial sync enabled state loaded: $_isSyncEnabled");
    // Register event handlers
    on<CheckSyncStatus>(_onCheckSyncStatus);
    on<UploadAccountsRequested>(_onUploadAccountsRequested);
    on<DownloadAccountsRequested>(_onDownloadAccountsRequested);
    on<ToggleSyncEnabled>(_onToggleSyncEnabled); // Ensure only one registration
    on<SyncNowRequested>(_onSyncNowRequested);
    on<SyncOverwriteCloudRequested>(
      _onSyncOverwriteCloudRequested,
    ); // Register new handler

    // Start listening to AccountsBloc
    _accountsSubscription = _accountsBloc.stream.listen(
      _onAccountsStateChanged,
    );
  }

  // --- Listener for AccountsBloc State Changes ---
  void _onAccountsStateChanged(AccountsState accountsState) {
    // Check if we are waiting for a merge operation to complete
    if (_mergeCompleter != null && !_mergeCompleter!.isCompleted) {
      if (accountsState is AccountsLoaded) {
        print(
          "[SyncBloc] AccountsBloc emitted AccountsLoaded after merge event. Completing merge.",
        );
        _mergeCompleter!.complete(accountsState.accounts);
      } else if (accountsState is AccountsError) {
        print(
          "[SyncBloc] AccountsBloc emitted AccountsError during merge. Completing merge with error.",
        );
        _mergeCompleter!.completeError(
          Exception(
            "AccountsBloc failed during merge: ${accountsState.message}",
          ),
        );
      }
      // Ignore other states like AccountsLoading while waiting for the final result
    }
  }

  // --- Event Handlers ---

  Future<void> _onCheckSyncStatus(
    CheckSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    // _isSyncEnabled is already loaded in the constructor
    emit(const SyncInProgress(message: 'Checking sync status...'));
    final hasDataResult = await _hasRemoteDataUseCase(NoParams());

    await hasDataResult.fold(
      (failure) async => emit(
        SyncFailure(message: failure.message, isSyncEnabled: _isSyncEnabled),
      ),
      (hasData) async {
        // If remote data status check succeeds, fetch the last upload time
        final timeResult = await _getLastSyncTimeUseCase(
          NoParams(),
        ); // Use renamed field
        final lastUploadTime = timeResult.getOrElse((_) => null);

        emit(
          SyncStatusChecked(
            isSyncEnabled: _isSyncEnabled,
            hasRemoteData: hasData,
            lastSyncTime:
                lastUploadTime, // Pass the fetched time as lastSyncTime state property
          ),
        );
      },
    );
  }

  Future<void> _onUploadAccountsRequested(
    UploadAccountsRequested event,
    Emitter<SyncState> emit,
  ) async {
    emit(const SyncInProgress(message: 'Uploading...'));
    final result = await _uploadAccountsUseCase(
      UploadAccountsParams(accounts: event.accountsToUpload),
    );
    result.fold(
      (failure) => emit(
        SyncFailure(message: failure.message, isSyncEnabled: _isSyncEnabled),
      ),
      (_) {
        emit(SyncSuccess(message: 'Accounts uploaded successfully.'));
        // Trigger status check to reflect the new last sync time
        add(CheckSyncStatus());
      },
    );
  }

  Future<void> _onDownloadAccountsRequested(
    DownloadAccountsRequested event,
    Emitter<SyncState> emit,
  ) async {
    emit(const SyncInProgress(message: 'Downloading...'));
    final result = await _downloadAccountsUseCase(NoParams());
    result.fold(
      (failure) => emit(
        SyncFailure(message: failure.message, isSyncEnabled: _isSyncEnabled),
      ),
      (downloadedAccounts) {
        // Assuming ReplaceAccountsEvent exists and handles merge/replace logic
        _accountsBloc.add(ReplaceAccountsEvent(accounts: downloadedAccounts));
        emit(SyncSuccess(message: 'Accounts downloaded successfully.'));
        // Trigger status check
        add(CheckSyncStatus());
      },
    );
  }

  Future<void> _onToggleSyncEnabled(
    ToggleSyncEnabled event,
    Emitter<SyncState> emit,
  ) async {
    _isSyncEnabled = event.isEnabled;
    // Save the new state to SharedPreferences
    await _prefs.setBool(_syncEnabledPrefKey, _isSyncEnabled);
    print("Sync enabled toggled to: $_isSyncEnabled"); // For debugging

    // Re-check status to reflect the change and get current data state
    add(CheckSyncStatus());
  }

  Future<void> _onSyncNowRequested(
    SyncNowRequested event,
    Emitter<SyncState> emit,
  ) async {
    if (!_isSyncEnabled) {
      emit(
        SyncFailure(
          message: 'Sync is disabled.',
          isSyncEnabled: _isSyncEnabled,
        ),
      );
      return;
    }

    // 1. Download
    emit(const SyncInProgress(message: 'Downloading...'));
    final downloadResult = await _downloadAccountsUseCase(NoParams());

    await downloadResult.fold(
      (failure) async => emit(
        SyncFailure(
          message: "Download failed: ${failure.message}",
          isSyncEnabled: _isSyncEnabled,
        ),
      ),
      (downloadedAccounts) async {
        // 2. Merge/Replace in AccountsBloc
        emit(const SyncInProgress(message: 'Updating local data...'));
        _accountsBloc.add(ReplaceAccountsEvent(accounts: downloadedAccounts));

        // --- Wait for AccountsBloc to finish processing ---
        _mergeCompleter = Completer<List<AuthenticatorAccount>>();
        List<AuthenticatorAccount> accountsToUpload; // Declare here
        try {
          print("[SyncBloc] Waiting for AccountsBloc merge completion...");
          // Wait for the completer, with a timeout
          accountsToUpload = await _mergeCompleter!.future.timeout(
            // Assign here
            const Duration(seconds: 10), // Adjust timeout as needed
            onTimeout: () {
              print("[SyncBloc] Timeout waiting for AccountsBloc merge.");
              throw TimeoutException("Timeout waiting for local data update");
            },
          );
          print(
            "[SyncBloc] AccountsBloc merge completed. Accounts to upload: ${accountsToUpload.length}",
          );
        } catch (e) {
          print("[SyncBloc] Error waiting for AccountsBloc merge: $e");
          emit(
            SyncFailure(
              message: "Failed to get updated local accounts: ${e.toString()}",
              isSyncEnabled: _isSyncEnabled,
            ),
          );
          _mergeCompleter = null; // Clean up completer
          return;
        } finally {
          _mergeCompleter = null; // Ensure completer is cleaned up
        }

        // Check if there's anything to upload *after* potential merge/replace
        if (accountsToUpload.isEmpty) {
          emit(
            SyncSuccess(message: 'Sync complete. Local data updated.'),
          ); // Adjusted message
          add(CheckSyncStatus()); // Refresh status
          return;
        }

        // 3. Upload (Confirmation is handled by UI)
        emit(const SyncInProgress(message: 'Uploading...'));
        final uploadResult = await _uploadAccountsUseCase(
          UploadAccountsParams(accounts: accountsToUpload),
        );

        uploadResult.fold(
          (failure) => emit(
            SyncFailure(
              message: "Upload failed: ${failure.message}",
              isSyncEnabled: _isSyncEnabled,
            ),
          ),
          (_) {
            emit(SyncSuccess(message: 'Sync completed successfully.'));
            // 4. Refresh status
            add(CheckSyncStatus());
          },
        );
      },
    );
  }

  Future<void> _onSyncOverwriteCloudRequested(
    SyncOverwriteCloudRequested event,
    Emitter<SyncState> emit,
  ) async {
    // This logic is essentially the same as a direct upload, overwriting the cloud.
    emit(
      const SyncInProgress(message: 'Overwriting cloud data...'),
    ); // Specific message
    final result = await _uploadAccountsUseCase(
      UploadAccountsParams(accounts: event.accountsToUpload),
    );
    result.fold(
      (failure) => emit(
        SyncFailure(
          message: "Overwrite failed: ${failure.message}",
          isSyncEnabled: _isSyncEnabled,
        ), // Specific error message prefix
      ),
      (_) {
        emit(
          SyncSuccess(message: 'Cloud data overwritten successfully.'),
        ); // Specific success message
        // Trigger status check to reflect the new last sync time
        add(CheckSyncStatus());
      },
    );
  }

  @override
  Future<void> close() {
    print("[SyncBloc] Closing SyncBloc and cancelling subscriptions.");
    _accountsSubscription?.cancel();
    // If a merge operation is somehow pending when the bloc closes, complete it with an error.
    if (_mergeCompleter != null && !_mergeCompleter!.isCompleted) {
      _mergeCompleter!.completeError('SyncBloc closed during merge operation.');
      _mergeCompleter = null;
    }
    return super.close();
  }
} // End of SyncBloc class

// TODO: Define ReplaceAccountsEvent in lib/features/authenticator/presentation/bloc/accounts_event.dart
/*
class ReplaceAccountsEvent extends AccountsEvent {
  final List<AuthenticatorAccount> accounts;
  const ReplaceAccountsEvent({required this.accounts});
  @override List<Object> get props => [accounts];
}
*/

// TODO: Add handler for ReplaceAccountsEvent in lib/features/authenticator/presentation/bloc/accounts_bloc.dart
/*
  Future<void> _onReplaceAccounts(
    ReplaceAccountsEvent event,
    Emitter<AccountsState> emit,
  ) async {
    emit(AccountsLoading()); // Or keep current state?
    // Implement merge logic here:
    // 1. Get current local accounts (if any)
    // 2. Create a map or set for efficient lookup of downloaded accounts.
    // 3. Iterate through local accounts: update if exists in downloaded, keep if not.
    // 4. Iterate through downloaded accounts: add if not already processed from local list.
    // 5. Clear existing local storage.
    // 6. Save the merged list back to local storage.
    // Example (simplified, assumes AddAccount handles updates):
    // await deleteAllAccounts(NoParams()); // Maybe not needed if AddAccount updates
    // final mergedAccounts = _performMerge(currentLocalAccounts, event.accounts);
    // for (final account in mergedAccounts) {
    //    await addAccount(AddAccountParams(account: account));
    // }
    add(LoadAccounts()); // Fetch accounts again to reflect changes
  }
*/
