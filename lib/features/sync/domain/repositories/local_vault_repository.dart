import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';

class LocalVaultConflict implements Exception {
  const LocalVaultConflict();
}

class LocalVaultSnapshot {
  const LocalVaultSnapshot({
    required this.generation,
    required this.accounts,
    required this.metadata,
    required this.deletedAccountIds,
  });
  final int generation;
  final List<AuthenticatorAccount> accounts;
  final AccountSyncMetadata metadata;
  final Set<String> deletedAccountIds;
}

/// One durable commit owns account payloads, cloud provenance and delete intent.
/// Network runs outside the transaction; stale generations cannot publish.
abstract interface class LocalVaultRepository {
  Future<LocalVaultSnapshot> readVault();
  Future<int> commitVault({
    required int expectedGeneration,
    required List<AuthenticatorAccount> accounts,
    required AccountSyncMetadata metadata,
    required Set<String> deletedAccountIds,
    required bool Function() canCommit,
  });
}
