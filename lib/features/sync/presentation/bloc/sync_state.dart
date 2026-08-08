part of 'sync_bloc.dart';

sealed class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => const [];
}

class SyncInitial extends SyncState {
  const SyncInitial();
}

class SyncSignedOut extends SyncState {
  const SyncSignedOut();
}

class SyncInProgress extends SyncState {
  const SyncInProgress();
}

class SyncReady extends SyncState {
  const SyncReady({
    required this.completedAt,
    required this.uploadedCount,
    required this.downloadedCount,
    required this.deletedCount,
  });

  final DateTime completedAt;
  final int uploadedCount;
  final int downloadedCount;
  final int deletedCount;

  @override
  List<Object?> get props => [
    completedAt,
    uploadedCount,
    downloadedCount,
    deletedCount,
  ];
}

class SyncFailure extends SyncState {
  const SyncFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];

  @override
  String toString() => 'SyncFailure(message: [REDACTED])';
}
