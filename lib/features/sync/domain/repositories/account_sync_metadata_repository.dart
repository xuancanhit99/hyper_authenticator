import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';

abstract class AccountSyncMetadataRepository {
  Future<AccountSyncMetadata> read();

  Future<void> write(AccountSyncMetadata metadata);
}
