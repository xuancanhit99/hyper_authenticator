import 'dart:convert';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/local_vault_repository.dart';

/// Atomic in-memory model for policy tests. Crash/CAS regressions use the real datasource.
class MemoryLocalVault implements LocalVaultRepository {
  MemoryLocalVault(this.accounts, this.readMetadata, this.saveMetadata);
  final List<AuthenticatorAccount> accounts;
  final AccountSyncMetadata Function() readMetadata;
  final void Function(AccountSyncMetadata) saveMetadata;
  int generation = 0;
  final versions = <int, String>{};
  Set<String> intents = {};
  String get _value => jsonEncode([
    accounts.map((a) => a.toJson()).toList(),
    readMetadata().toJson(),
  ]);
  @override
  Future<LocalVaultSnapshot> readVault() async {
    final metadata = readMetadata().mutableCopy();
    intents.addAll(
      metadata.records.entries
          .where(
            (e) => !e.value.isDeleted && !accounts.any((a) => a.id == e.key),
          )
          .map((e) => e.key),
    );
    final token = ++generation;
    versions[token] = _value;
    return LocalVaultSnapshot(
      generation: token,
      accounts: List.of(accounts),
      metadata: metadata,
      deletedAccountIds: Set.of(intents),
    );
  }

  @override
  Future<int> commitVault({
    required int expectedGeneration,
    required List<AuthenticatorAccount> accounts,
    required AccountSyncMetadata metadata,
    required Set<String> deletedAccountIds,
    required bool Function() canCommit,
  }) async {
    if (!canCommit() || versions[expectedGeneration] != _value) {
      throw const LocalVaultConflict();
    }
    this.accounts
      ..clear()
      ..addAll(accounts);
    saveMetadata(AccountSyncMetadata(Map.unmodifiable(metadata.records)));
    intents = Set.of(deletedAccountIds);
    versions[++generation] = _value;
    return generation;
  }
}
