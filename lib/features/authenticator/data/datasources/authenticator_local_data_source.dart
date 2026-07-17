import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

abstract class AuthenticatorLocalDataSourceException implements Exception {}

class StorageReadException extends AuthenticatorLocalDataSourceException {}

class StorageWriteException extends AuthenticatorLocalDataSourceException {}

class StorageDeleteException extends AuthenticatorLocalDataSourceException {}

class AccountNotFoundException extends AuthenticatorLocalDataSourceException {}

abstract class AuthenticatorLocalDataSource {
  Future<List<AuthenticatorAccount>> getAccounts();

  Future<AuthenticatorAccount> saveAccount(AuthenticatorAccount account);

  Future<void> deleteAccount(String id);

  Future<void> updateAccount(AuthenticatorAccount account);
}

@LazySingleton(as: AuthenticatorLocalDataSource)
class AuthenticatorLocalDataSourceImpl implements AuthenticatorLocalDataSource {
  static const _legacyAccountIndexKey = 'authenticator_account_index';
  static const _formatVersion = 2;
  static const _namespace = 'ha:v2:';
  static const _recordPrefix = '${_namespace}record:';
  static const _manifestPrefix = '${_namespace}manifest:';
  static const _commitPrefix = '${_namespace}commit:';

  static final RegExp _legacyAccountKeyPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  final FlutterSecureStorage secureStorage;
  final Uuid uuid;

  Future<void> _operationTail = Future<void>.value();

  AuthenticatorLocalDataSourceImpl({
    required this.secureStorage,
    required this.uuid,
  });

  @override
  Future<List<AuthenticatorAccount>> getAccounts() => _serialized(() async {
    try {
      final snapshot = await _ensureV2Snapshot();
      return List<AuthenticatorAccount>.unmodifiable(snapshot.accounts);
    } catch (_) {
      throw StorageReadException();
    }
  });

  @override
  Future<AuthenticatorAccount> saveAccount(AuthenticatorAccount account) =>
      _serialized(() async {
        final accountToSave = account.id.isEmpty
            ? AuthenticatorAccount(
                id: uuid.v4(),
                issuer: account.issuer,
                accountName: account.accountName,
                secretKey: account.secretKey,
                algorithm: account.algorithm,
                digits: account.digits,
                period: account.period,
              )
            : account;

        try {
          final current = await _ensureV2Snapshot();
          final accounts = List<AuthenticatorAccount>.from(current.accounts);
          final existingIndex = accounts.indexWhere(
            (stored) => stored.id == accountToSave.id,
          );
          if (existingIndex == -1) {
            accounts.add(accountToSave);
          } else {
            accounts[existingIndex] = accountToSave;
          }

          await _commitSnapshot(
            previous: current,
            accounts: accounts,
            changedAccountIds: <String>{accountToSave.id},
          );
          return accountToSave;
        } catch (_) {
          throw StorageWriteException();
        }
      });

  @override
  Future<void> deleteAccount(String id) => _serialized(() async {
    try {
      final current = await _ensureV2Snapshot();
      if (!current.entriesById.containsKey(id)) {
        throw AccountNotFoundException();
      }

      final accounts = current.accounts
          .where((account) => account.id != id)
          .toList(growable: false);
      await _commitSnapshot(
        previous: current,
        accounts: accounts,
        changedAccountIds: const <String>{},
      );
    } on AccountNotFoundException {
      rethrow;
    } catch (_) {
      throw StorageDeleteException();
    }
  });

  @override
  Future<void> updateAccount(AuthenticatorAccount account) =>
      _serialized(() async {
        try {
          final current = await _ensureV2Snapshot();
          final existingIndex = current.accounts.indexWhere(
            (stored) => stored.id == account.id,
          );
          if (existingIndex == -1) {
            throw AccountNotFoundException();
          }

          final accounts = List<AuthenticatorAccount>.from(current.accounts);
          accounts[existingIndex] = account;
          await _commitSnapshot(
            previous: current,
            accounts: accounts,
            changedAccountIds: <String>{account.id},
          );
        } on AccountNotFoundException {
          rethrow;
        } catch (_) {
          throw StorageWriteException();
        }
      });

  Future<_V2Snapshot> _ensureV2Snapshot() async {
    final storedValues = await secureStorage.readAll();
    final existing = _loadLatestCommittedSnapshot(storedValues);
    if (existing != null) {
      return existing;
    }

    final legacyAccounts = _loadLegacyAccounts(storedValues);
    return _commitSnapshot(
      previous: null,
      accounts: legacyAccounts,
      changedAccountIds: legacyAccounts.map((account) => account.id).toSet(),
    );
  }

  _V2Snapshot? _loadLatestCommittedSnapshot(Map<String, String> storedValues) {
    final commitEntries = storedValues.entries
        .where((entry) => entry.key.startsWith(_commitPrefix))
        .toList(growable: false);
    if (commitEntries.isEmpty) {
      return null;
    }

    final candidates = <_CommitCandidate>[];
    for (final entry in commitEntries) {
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is! Map<String, dynamic> ||
            decoded['formatVersion'] != _formatVersion ||
            decoded['generation'] is! int ||
            decoded['manifestKey'] is! String) {
          continue;
        }
        candidates.add(
          _CommitCandidate(
            commitKey: entry.key,
            generation: decoded['generation'] as int,
            manifestKey: decoded['manifestKey'] as String,
          ),
        );
      } catch (_) {
        // A damaged latest commit is recoverable if an older commit is valid.
      }
    }

    candidates.sort((left, right) {
      final generationOrder = right.generation.compareTo(left.generation);
      return generationOrder != 0
          ? generationOrder
          : right.commitKey.compareTo(left.commitKey);
    });

    for (final candidate in candidates) {
      try {
        return _loadManifest(candidate, storedValues);
      } catch (_) {
        // Continue to the previous committed generation.
      }
    }

    throw const FormatException('No valid committed local-storage snapshot.');
  }

  _V2Snapshot _loadManifest(
    _CommitCandidate candidate,
    Map<String, String> storedValues,
  ) {
    final manifestJson = storedValues[candidate.manifestKey];
    if (manifestJson == null ||
        !candidate.manifestKey.startsWith(_manifestPrefix)) {
      throw const FormatException('Manifest is missing.');
    }

    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map<String, dynamic> ||
        decoded['formatVersion'] != _formatVersion ||
        decoded['generation'] != candidate.generation ||
        decoded['records'] is! List<dynamic>) {
      throw const FormatException('Manifest shape is invalid.');
    }

    final accounts = <AuthenticatorAccount>[];
    final entriesById = <String, _V2RecordEntry>{};
    for (final descriptor in decoded['records'] as List<dynamic>) {
      if (descriptor is! Map<String, dynamic> ||
          descriptor['id'] is! String ||
          descriptor['recordKey'] is! String) {
        throw const FormatException('Record descriptor is invalid.');
      }

      final id = descriptor['id'] as String;
      final recordKey = descriptor['recordKey'] as String;
      if (id.isEmpty ||
          !recordKey.startsWith(_recordPrefix) ||
          entriesById.containsKey(id)) {
        throw const FormatException('Record identity is invalid.');
      }

      final recordJson = storedValues[recordKey];
      if (recordJson == null) {
        throw const FormatException('Record is missing.');
      }
      final record = AuthenticatorAccount.fromJson(
        jsonDecode(recordJson) as Map<String, dynamic>,
      );
      if (record.id != id) {
        throw const FormatException('Record identity does not match its key.');
      }

      accounts.add(record);
      entriesById[id] = _V2RecordEntry(recordKey: recordKey, account: record);
    }

    return _V2Snapshot(
      generation: candidate.generation,
      accounts: accounts,
      entriesById: entriesById,
    );
  }

  List<AuthenticatorAccount> _loadLegacyAccounts(
    Map<String, String> storedValues,
  ) {
    final accounts = <AuthenticatorAccount>[];
    final seenIds = <String>{};
    final indexJson = storedValues[_legacyAccountIndexKey];
    var indexedIds = const <String>[];

    if (indexJson != null && indexJson.isNotEmpty) {
      try {
        final decodedIndex = jsonDecode(indexJson);
        if (decodedIndex is List<dynamic> &&
            decodedIndex.every((id) => id is String)) {
          indexedIds = decodedIndex.cast<String>();
        }
      } catch (_) {
        // A corrupt legacy index is recoverable by scanning strict UUID keys.
      }
    }

    for (final id in indexedIds) {
      if (seenIds.contains(id)) {
        continue;
      }
      final recordJson = storedValues[id];
      if (recordJson == null) {
        // Repair the legacy delete failure mode by omitting dangling IDs.
        continue;
      }
      try {
        final account = AuthenticatorAccount.fromJson(
          jsonDecode(recordJson) as Map<String, dynamic>,
        );
        if (account.id != id) {
          throw const FormatException('Legacy record identity is invalid.');
        }
        seenIds.add(id);
        accounts.add(account);
      } catch (_) {
        // Skip a damaged record and continue recovering other UUID-keyed data.
      }
    }

    final orphanKeys =
        storedValues.keys
            .where(
              (key) =>
                  !seenIds.contains(key) &&
                  _legacyAccountKeyPattern.hasMatch(key),
            )
            .toList()
          ..sort();
    for (final key in orphanKeys) {
      try {
        final account = AuthenticatorAccount.fromJson(
          jsonDecode(storedValues[key]!) as Map<String, dynamic>,
        );
        if (account.id == key && seenIds.add(key)) {
          accounts.add(account);
        }
      } catch (_) {
        // Only strictly shaped UUID-keyed account records are recovered.
      }
    }

    return accounts;
  }

  Future<_V2Snapshot> _commitSnapshot({
    required _V2Snapshot? previous,
    required List<AuthenticatorAccount> accounts,
    required Set<String> changedAccountIds,
  }) async {
    final generation = (previous?.generation ?? 0) + 1;
    final transactionId = uuid.v4();
    final generationKey = generation.toString().padLeft(20, '0');
    final entriesById = <String, _V2RecordEntry>{};
    final recordDescriptors = <Map<String, String>>[];

    for (final account in accounts) {
      if (entriesById.containsKey(account.id)) {
        throw const FormatException('Duplicate account identity.');
      }

      final previousEntry = previous?.entriesById[account.id];
      final shouldWriteRecord =
          previousEntry == null || changedAccountIds.contains(account.id);
      final recordKey = shouldWriteRecord
          ? '$_recordPrefix${account.id}:$transactionId'
          : previousEntry.recordKey;

      if (shouldWriteRecord) {
        final recordJson = jsonEncode(account.toJson());
        await secureStorage.write(key: recordKey, value: recordJson);
        if (await secureStorage.read(key: recordKey) != recordJson) {
          throw const FormatException('Record verification failed.');
        }
      }

      entriesById[account.id] = _V2RecordEntry(
        recordKey: recordKey,
        account: account,
      );
      recordDescriptors.add(<String, String>{
        'id': account.id,
        'recordKey': recordKey,
      });
    }

    final manifestKey = '$_manifestPrefix$generationKey:$transactionId';
    final manifestJson = jsonEncode(<String, dynamic>{
      'formatVersion': _formatVersion,
      'generation': generation,
      'records': recordDescriptors,
    });
    await secureStorage.write(key: manifestKey, value: manifestJson);
    if (await secureStorage.read(key: manifestKey) != manifestJson) {
      throw const FormatException('Manifest verification failed.');
    }

    final commitKey = '$_commitPrefix$generationKey:$transactionId';
    final commitJson = jsonEncode(<String, dynamic>{
      'formatVersion': _formatVersion,
      'generation': generation,
      'manifestKey': manifestKey,
    });
    await secureStorage.write(key: commitKey, value: commitJson);
    if (await secureStorage.read(key: commitKey) != commitJson) {
      throw const FormatException('Commit verification failed.');
    }

    final verifiedValues = await secureStorage.readAll();
    final verified = _loadManifest(
      _CommitCandidate(
        commitKey: commitKey,
        generation: generation,
        manifestKey: manifestKey,
      ),
      verifiedValues,
    );
    if (verified.accounts.length != accounts.length) {
      throw const FormatException('Committed snapshot verification failed.');
    }
    return verified;
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _V2Snapshot {
  final int generation;
  final List<AuthenticatorAccount> accounts;
  final Map<String, _V2RecordEntry> entriesById;

  const _V2Snapshot({
    required this.generation,
    required this.accounts,
    required this.entriesById,
  });
}

class _V2RecordEntry {
  final String recordKey;
  final AuthenticatorAccount account;

  const _V2RecordEntry({required this.recordKey, required this.account});
}

class _CommitCandidate {
  final String commitKey;
  final int generation;
  final String manifestKey;

  const _CommitCandidate({
    required this.commitKey,
    required this.generation,
    required this.manifestKey,
  });
}
