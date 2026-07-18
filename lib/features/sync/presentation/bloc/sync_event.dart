part of 'sync_bloc.dart';

sealed class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => const [];
}

class CheckSyncStatus extends SyncEvent {
  const CheckSyncStatus();
}

class BeginEncryptedSyncSetup extends SyncEvent {
  const BeginEncryptedSyncSetup();
}

class ConfirmRecoveryKeySaved extends SyncEvent {
  const ConfirmRecoveryKeySaved();
}

class BeginRecoveryKeyRotation extends SyncEvent {
  const BeginRecoveryKeyRotation();
}

class ConfirmRecoveryKeyRotation extends SyncEvent {
  const ConfirmRecoveryKeyRotation();
}

class RecoverEncryptedSync extends SyncEvent {
  final String recoveryCode;

  const RecoverEncryptedSync(this.recoveryCode);

  @override
  List<Object?> get props => [recoveryCode];

  @override
  String toString() => 'RecoverEncryptedSync(recoveryCode: [REDACTED])';
}

class SetEncryptedSyncEnabled extends SyncEvent {
  final bool enabled;

  const SetEncryptedSyncEnabled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

class SyncNowRequested extends SyncEvent {
  const SyncNowRequested();
}

class ResolveSyncConflictWithCloud extends SyncEvent {
  const ResolveSyncConflictWithCloud();
}

class ResolveSyncConflictWithLocal extends SyncEvent {
  const ResolveSyncConflictWithLocal();
}

class CancelSensitiveSyncOperation extends SyncEvent {
  const CancelSensitiveSyncOperation();
}
