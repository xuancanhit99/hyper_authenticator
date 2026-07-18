part of 'sync_bloc.dart';

sealed class SyncState extends Equatable {
  const SyncState();

  @override
  List<Object?> get props => const [];
}

class SyncInitial extends SyncState {
  const SyncInitial();
}

class SyncUnavailable extends SyncState {
  final String message;

  const SyncUnavailable(this.message);

  @override
  List<Object?> get props => [message];
}

class SyncInProgress extends SyncState {
  final String message;

  const SyncInProgress(this.message);

  @override
  List<Object?> get props => [message];
}

class SyncSetupRequired extends SyncState {
  const SyncSetupRequired();
}

class SyncRecoveryRequired extends SyncState {
  final DateTime remoteUpdatedAt;

  const SyncRecoveryRequired(this.remoteUpdatedAt);

  @override
  List<Object?> get props => [remoteUpdatedAt];
}

class SyncRecoveryKeyReady extends SyncState {
  final String recoveryCode;

  const SyncRecoveryKeyReady(this.recoveryCode);

  @override
  List<Object?> get props => [recoveryCode];

  @override
  String toString() => 'SyncRecoveryKeyReady(recoveryCode: [REDACTED])';
}

class SyncRecoveryKeyRotationReady extends SyncState {
  final String recoveryCode;

  const SyncRecoveryKeyRotationReady(this.recoveryCode);

  @override
  List<Object?> get props => [recoveryCode];

  @override
  String toString() => 'SyncRecoveryKeyRotationReady(recoveryCode: [REDACTED])';
}

class SyncVaultKeyRotationReady extends SyncState {
  final String recoveryCode;

  const SyncVaultKeyRotationReady(this.recoveryCode);

  @override
  List<Object?> get props => [recoveryCode];

  @override
  String toString() => 'SyncVaultKeyRotationReady(recoveryCode: [REDACTED])';
}

class SyncReady extends SyncState {
  final bool isEnabled;
  final int revision;
  final DateTime updatedAt;

  const SyncReady({
    required this.isEnabled,
    required this.revision,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [isEnabled, revision, updatedAt];
}

class SyncConflict extends SyncState {
  final int remoteRevision;
  final DateTime remoteUpdatedAt;

  const SyncConflict({
    required this.remoteRevision,
    required this.remoteUpdatedAt,
  });

  @override
  List<Object?> get props => [remoteRevision, remoteUpdatedAt];
}

class SyncSuccess extends SyncState {
  final int revision;
  final DateTime completedAt;

  const SyncSuccess({required this.revision, required this.completedAt});

  @override
  List<Object?> get props => [revision, completedAt];
}

class SyncFailure extends SyncState {
  final String message;
  final bool isConflict;

  const SyncFailure(this.message, {this.isConflict = false});

  @override
  List<Object?> get props => [message, isConflict];
}
