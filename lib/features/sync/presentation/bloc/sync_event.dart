part of 'sync_bloc.dart'; // Will create sync_bloc.dart next

abstract class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => [];
}

/// Event to check if remote data exists and the general sync status.
class CheckSyncStatus extends SyncEvent {}

/// Event triggered to upload the current local accounts to the remote server.
class UploadAccountsRequested extends SyncEvent {
  final List<AuthenticatorAccount> accountsToUpload;

  const UploadAccountsRequested({required this.accountsToUpload});

  @override
  List<Object?> get props => [accountsToUpload];
}

/// Event triggered to download accounts from the remote server and overwrite local ones.
class DownloadAccountsRequested extends SyncEvent {}

/// Event to toggle the sync feature on or off.
class ToggleSyncEnabled extends SyncEvent {
  final bool isEnabled;

  const ToggleSyncEnabled({required this.isEnabled});

  @override
  List<Object?> get props => [isEnabled];
}

/// Event triggered by the "Sync Now" button.
/// Performs Download (add only), Merge (implicit), Confirm, Upload (overwrite).
class SyncNowRequested extends SyncEvent {
  // Although download happens first, we need the current local accounts
  // for the potential upload step after confirmation.
  final List<AuthenticatorAccount> accountsToUpload;

  const SyncNowRequested({required this.accountsToUpload});

  @override
  List<Object?> get props => [accountsToUpload];
}

/// Event triggered to explicitly overwrite cloud data with local data.
class SyncOverwriteCloudRequested extends SyncEvent {
  final List<AuthenticatorAccount> accountsToUpload;

  const SyncOverwriteCloudRequested({required this.accountsToUpload});

  @override
  List<Object?> get props => [accountsToUpload];
}

// Add other events as needed, e.g., for setting up sync (password), deleting remote data etc.
