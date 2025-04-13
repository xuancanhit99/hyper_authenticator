part of 'sync_bloc.dart'; // Will create sync_bloc.dart next

abstract class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any sync operation has started.
class SyncInitial extends SyncState {}

/// State indicating a sync operation (check, upload, download) is in progress.
class SyncInProgress extends SyncState {}

/// State after checking the remote server status.
class SyncStatusChecked extends SyncState {
  final bool hasRemoteData;
  final DateTime?
  lastSyncTime; // Optional: Could store last successful sync time

  const SyncStatusChecked({required this.hasRemoteData, this.lastSyncTime});

  @override
  List<Object?> get props => [hasRemoteData, lastSyncTime];
}

/// State indicating a sync operation (upload or download) completed successfully.
class SyncSuccess extends SyncState {
  final String
  message; // e.g., "Accounts uploaded successfully." or "Accounts downloaded."
  final DateTime timestamp;

  SyncSuccess({required this.message})
    : timestamp = DateTime.now(); // Removed const

  @override
  List<Object?> get props => [message, timestamp];
}

/// State indicating an error occurred during a sync operation.
class SyncFailure extends SyncState {
  final String message;

  const SyncFailure({required this.message});

  @override
  List<Object?> get props => [message];
}
