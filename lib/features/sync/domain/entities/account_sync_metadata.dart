class AccountSyncMetadataException implements Exception {
  const AccountSyncMetadataException();
}

class SyncedAccountMetadata {
  const SyncedAccountMetadata({
    required this.ownerUserId,
    required this.remoteRevision,
    required this.syncedFingerprint,
    required this.isDeleted,
  });

  final String ownerUserId;
  final int remoteRevision;
  final String? syncedFingerprint;
  final bool isDeleted;

  SyncedAccountMetadata copyWith({
    int? remoteRevision,
    String? syncedFingerprint,
    bool clearSyncedFingerprint = false,
    bool? isDeleted,
  }) => SyncedAccountMetadata(
    ownerUserId: ownerUserId,
    remoteRevision: remoteRevision ?? this.remoteRevision,
    syncedFingerprint: clearSyncedFingerprint
        ? null
        : syncedFingerprint ?? this.syncedFingerprint,
    isDeleted: isDeleted ?? this.isDeleted,
  );

  Map<String, Object?> toJson() => {
    'ownerUserId': ownerUserId,
    'remoteRevision': remoteRevision,
    'syncedFingerprint': syncedFingerprint,
    'isDeleted': isDeleted,
  };

  factory SyncedAccountMetadata.fromJson(Map<String, dynamic> json) {
    final ownerUserId = json['ownerUserId'];
    final remoteRevision = json['remoteRevision'];
    final syncedFingerprint = json['syncedFingerprint'];
    final isDeleted = json['isDeleted'];
    if (ownerUserId is! String ||
        ownerUserId.isEmpty ||
        remoteRevision is! int ||
        remoteRevision < 0 ||
        (syncedFingerprint != null && syncedFingerprint is! String) ||
        isDeleted is! bool) {
      throw const FormatException('Sync metadata record không hợp lệ.');
    }
    return SyncedAccountMetadata(
      ownerUserId: ownerUserId,
      remoteRevision: remoteRevision,
      syncedFingerprint: syncedFingerprint as String?,
      isDeleted: isDeleted,
    );
  }
}

class AccountSyncMetadata {
  const AccountSyncMetadata(this.records);

  final Map<String, SyncedAccountMetadata> records;

  Map<String, Object?> toJson() => {
    'formatVersion': 1,
    'records': {
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    },
  };

  factory AccountSyncMetadata.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['formatVersion'] != 1 ||
        value['records'] is! Map<String, dynamic>) {
      throw const AccountSyncMetadataException();
    }
    final records = <String, SyncedAccountMetadata>{};
    for (final entry in (value['records'] as Map<String, dynamic>).entries) {
      if (entry.key.isEmpty || entry.value is! Map<String, dynamic>) {
        throw const AccountSyncMetadataException();
      }
      records[entry.key] = SyncedAccountMetadata.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
    return AccountSyncMetadata(Map.unmodifiable(records));
  }

  AccountSyncMetadata mutableCopy() =>
      AccountSyncMetadata(Map<String, SyncedAccountMetadata>.from(records));
}
