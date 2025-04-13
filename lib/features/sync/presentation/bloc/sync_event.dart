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

// Add other events as needed, e.g., for setting up sync (password), deleting remote data etc.
