abstract class EncryptedSyncMetadataRepository {
  int? readLastRevision(String userId);

  Future<void> writeLastRevision(String userId, int revision);

  bool readEnabled(String userId);

  Future<void> writeEnabled(String userId, bool enabled);
}
