sealed class EncryptedSyncResult {
  const EncryptedSyncResult();
}

class EncryptedSyncSetupRequired extends EncryptedSyncResult {
  const EncryptedSyncSetupRequired();
}

class EncryptedSyncRecoveryRequired extends EncryptedSyncResult {
  final DateTime updatedAt;

  const EncryptedSyncRecoveryRequired(this.updatedAt);
}

class EncryptedSyncRecoveryKeyReady extends EncryptedSyncResult {
  final String recoveryCode;

  const EncryptedSyncRecoveryKeyReady(this.recoveryCode);
}

class EncryptedSyncReady extends EncryptedSyncResult {
  final bool isEnabled;
  final int revision;
  final DateTime updatedAt;

  const EncryptedSyncReady({
    required this.isEnabled,
    required this.revision,
    required this.updatedAt,
  });
}

class EncryptedSyncConflict extends EncryptedSyncResult {
  final int remoteRevision;
  final DateTime remoteUpdatedAt;

  const EncryptedSyncConflict({
    required this.remoteRevision,
    required this.remoteUpdatedAt,
  });
}

class EncryptedSyncCompleted extends EncryptedSyncResult {
  final int revision;
  final DateTime completedAt;

  const EncryptedSyncCompleted({
    required this.revision,
    required this.completedAt,
  });
}
