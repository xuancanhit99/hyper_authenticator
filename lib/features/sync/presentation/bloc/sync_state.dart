part of 'sync_bloc.dart'; // Will create sync_bloc.dart next

abstract class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any sync operation has started.
class SyncInitial extends SyncState {}

/// State indicating a sync operation (check, upload, download) is in progress.
class SyncInProgress extends SyncState {
  final String
  message; // e.g., "Checking status...", "Downloading...", "Uploading..."

  const SyncInProgress({this.message = 'Syncing...'}); // Default message

  @override
  List<Object?> get props => [message];
}

/// State after checking the remote server status.
class SyncStatusChecked extends SyncState {
  final bool isSyncEnabled; // Added: Is sync functionally enabled?
  final bool hasRemoteData;
  final DateTime? lastSyncTime; // Renamed from lastUploadTime

  const SyncStatusChecked({
    required this.isSyncEnabled, // Added
    required this.hasRemoteData,
    this.lastSyncTime,
  }); // Updated constructor

  @override
  List<Object?> get props => [isSyncEnabled, hasRemoteData, lastSyncTime]; // Updated props
}

/// State indicating a sync operation (upload or download) completed successfully.
class SyncSuccess extends SyncState {
  final String
  message; // e.g., "Accounts uploaded successfully." or "Accounts downloaded."
  final DateTime
  lastSyncTime; // Renamed from timestamp, represents the time of this success
  // Consider making message optional or more specific if needed
  SyncSuccess({required this.message})
    : lastSyncTime =
          DateTime.now(); // Use the time of success as last sync time

  @override
  List<Object?> get props => [message, lastSyncTime];
}

/// State indicating an error occurred during a sync operation.
class SyncFailure extends SyncState {
  final String message;
  final bool
  isSyncEnabled; // Added: Reflects the enabled state when failure occurred

  const SyncFailure({
    required this.message,
    required this.isSyncEnabled,
  }); // Added isSyncEnabled

  @override
  List<Object?> get props => [message, isSyncEnabled]; // Added isSyncEnabled
}
