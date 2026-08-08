import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_metadata.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_metadata_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: AccountSyncMetadataRepository)
class AccountSyncMetadataStore implements AccountSyncMetadataRepository {
  static const _storageKey = 'ha:cloud-sync:v1:metadata';
  static const _formatVersion = 1;

  AccountSyncMetadataStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<AccountSyncMetadata> read() async {
    try {
      final encoded = await _storage.read(key: _storageKey);
      if (encoded == null) return const AccountSyncMetadata({});
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['formatVersion'] != _formatVersion ||
          decoded['records'] is! Map<String, dynamic>) {
        throw const FormatException('Sync metadata không hợp lệ.');
      }
      final rawRecords = decoded['records'] as Map<String, dynamic>;
      final records = <String, SyncedAccountMetadata>{};
      for (final entry in rawRecords.entries) {
        if (entry.key.isEmpty || entry.value is! Map<String, dynamic>) {
          throw const FormatException('Sync metadata record không hợp lệ.');
        }
        records[entry.key] = SyncedAccountMetadata.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
      return AccountSyncMetadata(Map.unmodifiable(records));
    } catch (_) {
      throw const AccountSyncMetadataException();
    }
  }

  @override
  Future<void> write(AccountSyncMetadata metadata) async {
    try {
      final records = <String, Object?>{
        for (final entry in metadata.records.entries)
          entry.key: entry.value.toJson(),
      };
      await _storage.write(
        key: _storageKey,
        value: jsonEncode({
          'formatVersion': _formatVersion,
          'records': records,
        }),
      );
      final verified = await read();
      if (!_sameMetadata(verified, metadata)) {
        throw const FormatException('Sync metadata verify thất bại.');
      }
    } catch (_) {
      throw const AccountSyncMetadataException();
    }
  }

  bool _sameMetadata(AccountSyncMetadata first, AccountSyncMetadata second) {
    if (first.records.length != second.records.length) return false;
    for (final entry in first.records.entries) {
      final other = second.records[entry.key];
      if (other == null ||
          other.ownerUserId != entry.value.ownerUserId ||
          other.remoteRevision != entry.value.remoteRevision ||
          other.syncedFingerprint != entry.value.syncedFingerprint ||
          other.isDeleted != entry.value.isDeleted) {
        return false;
      }
    }
    return true;
  }
}
