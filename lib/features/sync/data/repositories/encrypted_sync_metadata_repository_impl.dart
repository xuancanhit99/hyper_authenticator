import 'package:hyper_authenticator/features/sync/domain/repositories/encrypted_sync_metadata_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

@LazySingleton(as: EncryptedSyncMetadataRepository)
class EncryptedSyncMetadataRepositoryImpl
    implements EncryptedSyncMetadataRepository {
  static const _revisionPrefix = 'ha:e2ee:last_revision:';
  static const _enabledPrefix = 'ha:e2ee:enabled:';

  final SharedPreferences _preferences;

  EncryptedSyncMetadataRepositoryImpl(this._preferences);

  @override
  int? readLastRevision(String userId) =>
      _preferences.getInt('$_revisionPrefix$userId');

  @override
  Future<void> writeLastRevision(String userId, int revision) =>
      _preferences.setInt('$_revisionPrefix$userId', revision);

  @override
  bool readEnabled(String userId) =>
      _preferences.getBool('$_enabledPrefix$userId') ?? false;

  @override
  Future<void> writeEnabled(String userId, bool enabled) =>
      _preferences.setBool('$_enabledPrefix$userId', enabled);
}
