import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart'; // Needed to update accounts after download
import 'package:hyper_authenticator/features/sync/domain/usecases/download_accounts_usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/get_last_sync_time_usecase.dart'; // Use case class renamed to GetLastSyncTimeUseCase
import 'package:hyper_authenticator/features/sync/domain/usecases/has_remote_data_usecase.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/merge_accounts_usecase.dart';
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
  final MergeAccountsUseCase _mergeAccountsUseCase;
  final GetLastSyncTimeUseCase // Use renamed class
  _getLastSyncTimeUseCase; // Rename field for consistency
  final AccountsBloc _accountsBloc;
  final SharedPreferences _prefs; // Add SharedPreferences dependency
  final AppConfig _appConfig;

  // --- State for Sync Enabled ---
  // TODO: Persist this state using SharedPreferences or similar
  bool _isSyncEnabled = false;

  static const String _syncEnabledPrefKey =
      'sync_enabled'; // Define key for preference

  SyncBloc(
    this._hasRemoteDataUseCase,
    this._uploadAccountsUseCase,
    this._downloadAccountsUseCase,
    this._mergeAccountsUseCase,
    this._getLastSyncTimeUseCase, // Use renamed parameter
    this._accountsBloc,
    this._prefs, // Inject SharedPreferences
    this._appConfig,
  ) : super(SyncInitial()) {
    // Load initial sync enabled state
    _isSyncEnabled =
        _appConfig.plaintextSyncAvailable &&
        (_prefs.getBool(_syncEnabledPrefKey) ?? false);
    // Register event handlers
    on<CheckSyncStatus>(_onCheckSyncStatus);
    on<UploadAccountsRequested>(_onUploadAccountsRequested);
    on<DownloadAccountsRequested>(_onDownloadAccountsRequested);
    on<ToggleSyncEnabled>(_onToggleSyncEnabled); // Ensure only one registration
    on<SyncNowRequested>(_onSyncNowRequested);
    on<SyncOverwriteCloudRequested>(
      _onSyncOverwriteCloudRequested,
    ); // Register new handler
  }

  // --- Event Handlers ---

  Future<void> _onCheckSyncStatus(
    CheckSyncStatus event,
    Emitter<SyncState> emit,
  ) async {
    if (!_appConfig.plaintextSyncAvailable) {
      emit(
        const SyncUnavailable(
          message:
              'Cloud sync tạm khóa cho đến khi mã hóa đầu cuối được triển khai.',
        ),
      );
      return;
    }
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
    if (!_ensureSyncAvailable(emit)) {
      return;
    }
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
    if (!_ensureSyncAvailable(emit)) {
      return;
    }
    emit(const SyncInProgress(message: 'Downloading...'));
    final result = await _downloadAccountsUseCase(NoParams());
    await result.fold(
      (failure) async => emit(
        SyncFailure(message: failure.message, isSyncEnabled: _isSyncEnabled),
      ),
      (downloadedAccounts) async {
        emit(const SyncInProgress(message: 'Updating local data...'));
        final mergeResult = await _mergeAccountsUseCase(downloadedAccounts);
        mergeResult.fold(
          (failure) => emit(
            SyncFailure(
              message: 'Local merge failed: ${failure.message}',
              isSyncEnabled: _isSyncEnabled,
            ),
          ),
          (_) {
            _accountsBloc.add(LoadAccounts());
            emit(SyncSuccess(message: 'Accounts downloaded successfully.'));
            add(CheckSyncStatus());
          },
        );
      },
    );
  }

  Future<void> _onToggleSyncEnabled(
    ToggleSyncEnabled event,
    Emitter<SyncState> emit,
  ) async {
    if (!_appConfig.plaintextSyncAvailable) {
      _isSyncEnabled = false;
      await _prefs.remove(_syncEnabledPrefKey);
      emit(
        const SyncUnavailable(
          message:
              'Không thể bật cloud sync plaintext. Hãy chờ phiên bản E2EE.',
        ),
      );
      return;
    }
    _isSyncEnabled = event.isEnabled;
    // Save the new state to SharedPreferences
    await _prefs.setBool(_syncEnabledPrefKey, _isSyncEnabled);

    // Re-check status to reflect the change and get current data state
    add(CheckSyncStatus());
  }

  Future<void> _onSyncNowRequested(
    SyncNowRequested event,
    Emitter<SyncState> emit,
  ) async {
    if (!_ensureSyncAvailable(emit)) {
      return;
    }
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
        // 2. Persist the merge directly through the domain boundary.
        emit(const SyncInProgress(message: 'Updating local data...'));
        final mergeResult = await _mergeAccountsUseCase(downloadedAccounts);
        Failure? mergeFailure;
        List<AuthenticatorAccount>? accountsToUpload;
        mergeResult.fold(
          (failure) => mergeFailure = failure,
          (accounts) => accountsToUpload = accounts,
        );
        if (mergeFailure != null) {
          emit(
            SyncFailure(
              message: 'Local merge failed: ${mergeFailure!.message}',
              isSyncEnabled: _isSyncEnabled,
            ),
          );
          return;
        }
        _accountsBloc.add(LoadAccounts());

        // Check if there's anything to upload *after* potential merge/replace
        if (accountsToUpload!.isEmpty) {
          emit(
            SyncSuccess(message: 'Sync complete. Local data updated.'),
          ); // Adjusted message
          add(CheckSyncStatus()); // Refresh status
          return;
        }

        // 3. Upload (Confirmation is handled by UI)
        emit(const SyncInProgress(message: 'Uploading...'));
        final uploadResult = await _uploadAccountsUseCase(
          UploadAccountsParams(accounts: accountsToUpload!),
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
    if (!_ensureSyncAvailable(emit)) {
      return;
    }
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

  bool _ensureSyncAvailable(Emitter<SyncState> emit) {
    if (_appConfig.plaintextSyncAvailable) {
      return true;
    }

    emit(
      const SyncUnavailable(
        message: 'Cloud sync plaintext đã bị khóa để bảo vệ TOTP secret.',
      ),
    );
    return false;
  }
} // End of SyncBloc class
