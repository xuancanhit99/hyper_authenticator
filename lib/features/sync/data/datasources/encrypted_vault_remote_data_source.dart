import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/sync/data/models/remote_encrypted_vault_snapshot.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool isEncryptedVaultRevisionConflict({
  required String? code,
  required String message,
}) {
  return code == 'PT409' || message.contains('revision_conflict');
}

class EncryptedVaultRevisionConflictException implements Exception {
  const EncryptedVaultRevisionConflictException();
}

@lazySingleton
class EncryptedVaultRemoteDataSource {
  static const tableName = 'encrypted_vault_snapshots';
  static const publishFunctionName = 'publish_encrypted_vault_snapshot';
  final SupabaseClient _client;

  EncryptedVaultRemoteDataSource(this._client);

  Future<RemoteEncryptedVaultSnapshot?> download({
    required String userId,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final row = await _client.from(tableName).select().maybeSingle();
      if (row == null) {
        return null;
      }
      return RemoteEncryptedVaultSnapshot.fromRow(row);
    } on PostgrestException {
      throw const ServerException('Không thể tải encrypted vault snapshot.');
    } on FormatException {
      throw const ServerException('Encrypted vault snapshot có format lỗi.');
    }
  }

  Future<int> publish({
    required String userId,
    required int expectedRevision,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        publishFunctionName,
        params: encryptedVaultPublishParameters(
          expectedRevision: expectedRevision,
          envelope: envelope,
          wrappedDataKey: wrappedDataKey,
        ),
      );
      if (response is! List || response.length != 1) {
        throw const FormatException('Publish response không hợp lệ.');
      }
      final row = response.single;
      if (row is! Map || row['revision'] is! int) {
        throw const FormatException('Publish revision không hợp lệ.');
      }
      final publishedRevision = row['revision'] as int;
      if (publishedRevision != envelope.revision ||
          publishedRevision != expectedRevision + 1) {
        throw const FormatException('Publish revision không khớp request.');
      }
      return publishedRevision;
    } on PostgrestException catch (error) {
      if (isEncryptedVaultRevisionConflict(
        code: error.code,
        message: error.message,
      )) {
        throw const EncryptedVaultRevisionConflictException();
      }
      throw const ServerException(
        'Không thể publish encrypted vault snapshot.',
      );
    } on FormatException {
      throw const ServerException(
        'Encrypted vault publish response có format lỗi.',
      );
    }
  }

  void _requireAuthenticatedUser(String expectedUserId) {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('User not logged in');
    }
    if (currentUser.id != expectedUserId) {
      throw const AuthException('Authenticated user changed during sync');
    }
  }
}
