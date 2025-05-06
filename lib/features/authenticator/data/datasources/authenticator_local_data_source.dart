import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:uuid/uuid.dart'; // For generating unique IDs
import 'package:injectable/injectable.dart'; // Moved import here

// Define potential errors for the data source
abstract class AuthenticatorLocalDataSourceException implements Exception {}

class StorageReadException extends AuthenticatorLocalDataSourceException {}

class StorageWriteException extends AuthenticatorLocalDataSourceException {}

class StorageDeleteException extends AuthenticatorLocalDataSourceException {}

class AccountNotFoundException extends AuthenticatorLocalDataSourceException {}

abstract class AuthenticatorLocalDataSource {
  /// Fetches all stored [AuthenticatorAccount]s.
  ///
  /// Throws [StorageReadException] if reading fails.
  Future<List<AuthenticatorAccount>> getAccounts();

  /// Saves a new [AuthenticatorAccount].
  /// Assigns a unique ID if the account doesn't have one.
  ///
  /// Throws [StorageWriteException] if saving fails.
  /// Returns the saved account (with ID).
  Future<AuthenticatorAccount> saveAccount(AuthenticatorAccount account);

  /// Deletes the account with the given [id].
  ///
  /// Throws [StorageDeleteException] if deletion fails.
  /// Throws [AccountNotFoundException] if the account doesn't exist.
  Future<void> deleteAccount(String id);

  /// Updates an existing [AuthenticatorAccount].
  ///
  /// Throws [StorageWriteException] if saving fails.
  /// Throws [AccountNotFoundException] if the account with the given ID doesn't exist.
  Future<void> updateAccount(AuthenticatorAccount account);
}

@LazySingleton(as: AuthenticatorLocalDataSource) // Register as implementation
class AuthenticatorLocalDataSourceImpl implements AuthenticatorLocalDataSource {
  final FlutterSecureStorage secureStorage;
  final Uuid uuid; // Inject Uuid

  // Key used to store the list of account IDs in secure storage
  static const _accountIndexKey = 'authenticator_account_index';

  AuthenticatorLocalDataSourceImpl({
    required this.secureStorage,
    required this.uuid,
  });

  // Helper to get the list of account IDs
  Future<List<String>> _getAccountIds() async {
    try {
      final indexJson = await secureStorage.read(key: _accountIndexKey);
      if (indexJson == null || indexJson.isEmpty) {
        return [];
      }
      return List<String>.from(jsonDecode(indexJson));
    } catch (e) {
      // Consider logging the error e
      throw StorageReadException();
    }
  }

  // Helper to save the list of account IDs
  Future<void> _saveAccountIds(List<String> ids) async {
    try {
      await secureStorage.write(key: _accountIndexKey, value: jsonEncode(ids));
    } catch (e) {
      // Consider logging the error e
      throw StorageWriteException();
    }
  }

  @override
  Future<List<AuthenticatorAccount>> getAccounts() async {
    final accountIds = await _getAccountIds();
    final accounts = <AuthenticatorAccount>[];
    try {
      for (final id in accountIds) {
        final accountJson = await secureStorage.read(key: id);
        if (accountJson != null) {
          accounts.add(AuthenticatorAccount.fromJson(jsonDecode(accountJson)));
        } else {
          // Handle inconsistency: ID in index but data missing?
          // Option: Log warning, remove ID from index? For now, just skip.
          print('Warning: Account data not found for ID: $id');
        }
      }
      return accounts;
    } catch (e) {
      // Consider logging the error e
      throw StorageReadException();
    }
  }

  @override
  Future<AuthenticatorAccount> saveAccount(AuthenticatorAccount account) async {
    // Assign a new UUID if the account ID is empty or doesn't conform (optional check)
    final accountToSave =
        account.id.isEmpty
            ? AuthenticatorAccount(
              id: uuid.v4(), // Generate a new ID
              issuer: account.issuer,
              accountName: account.accountName,
              secretKey: account.secretKey,
            )
            : account;

    try {
      final accountJson = jsonEncode(accountToSave.toJson());
      await secureStorage.write(key: accountToSave.id, value: accountJson);

      // Update the index
      final currentIds = await _getAccountIds();
      if (!currentIds.contains(accountToSave.id)) {
        currentIds.add(accountToSave.id);
        await _saveAccountIds(currentIds);
      }
      return accountToSave; // Return the account with the potentially new ID
    } catch (e) {
      // Consider logging the error e
      throw StorageWriteException();
    }
  }

  @override
  Future<void> deleteAccount(String id) async {
    try {
      // Check if account exists before deleting index entry
      final existingData = await secureStorage.read(key: id);
      if (existingData == null) {
        throw AccountNotFoundException();
      }

      await secureStorage.delete(key: id);

      // Update the index
      final currentIds = await _getAccountIds();
      if (currentIds.contains(id)) {
        currentIds.remove(id);
        await _saveAccountIds(currentIds);
      }
    } on AccountNotFoundException {
      rethrow; // Re-throw specific exception
    } catch (e) {
      // Consider logging the error e
      throw StorageDeleteException();
    }
  }

  @override
  Future<void> updateAccount(AuthenticatorAccount account) async {
    try {
      // First, check if the account exists by trying to read it.
      // This ensures we don't create a new entry if an update is intended for a non-existent ID.
      final existingAccountJson = await secureStorage.read(key: account.id);
      if (existingAccountJson == null) {
        throw AccountNotFoundException(); // Account to update not found
      }

      // If it exists, overwrite it with the new data.
      final accountJson = jsonEncode(account.toJson());
      await secureStorage.write(key: account.id, value: accountJson);
      // The index of account IDs does not need to be changed for an update,
      // as the ID remains the same and is already in the index.
    } on AccountNotFoundException {
      rethrow; // Re-throw to be caught by the repository
    } catch (e) {
      // Consider logging the error e
      throw StorageWriteException(); // Use StorageWriteException for update failures too
    }
  }
}
