part of 'sync_bloc.dart';

sealed class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => const [];
}

class CheckSyncStatus extends SyncEvent {
  const CheckSyncStatus();
}

class SyncNowRequested extends SyncEvent {
  const SyncNowRequested();
}

class _AuthSyncRequested extends SyncEvent {
  const _AuthSyncRequested(this.userId);

  final String? userId;

  @override
  List<Object?> get props => [userId];
}

class _LocalMutationSyncRequested extends SyncEvent {
  const _LocalMutationSyncRequested();
}

class _RealtimeSyncRequested extends SyncEvent {
  const _RealtimeSyncRequested(this.userId);

  final String userId;

  @override
  List<Object?> get props => [userId];
}
