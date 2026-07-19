import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/sync/data/models/remote_encrypted_vault_snapshot.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
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
  static const publishV2FunctionName = 'publish_encrypted_vault_snapshot_v2';
  static const rotateDeviceKeysFunctionName =
      'rotate_encrypted_vault_device_keys';
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

  Future<int> publishV2({
    required String userId,
    required int expectedRevision,
    required int expectedKeyGeneration,
    required List<int> bindingSecretBytes,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        publishV2FunctionName,
        params: encryptedVaultPublishV2Parameters(
          expectedRevision: expectedRevision,
          expectedKeyGeneration: expectedKeyGeneration,
          bindingSecretBytes: bindingSecretBytes,
          envelope: envelope,
          wrappedDataKey: wrappedDataKey,
        ),
      );
      if (response is! List || response.length != 1) {
        throw const FormatException('Publish v2 response không hợp lệ.');
      }
      final row = response.single;
      if (row is! Map ||
          row['revision'] is! int ||
          row['key_generation'] != expectedKeyGeneration ||
          row['device_wrap_version'] != 1) {
        throw const FormatException('Publish v2 version không hợp lệ.');
      }
      final publishedRevision = row['revision'] as int;
      if (publishedRevision != envelope.revision ||
          publishedRevision != expectedRevision + 1) {
        throw const FormatException('Publish v2 revision không khớp request.');
      }
      return publishedRevision;
    } on PostgrestException catch (error) {
      if (isEncryptedVaultRevisionConflict(
        code: error.code,
        message: error.message,
      )) {
        throw const EncryptedVaultRevisionConflictException();
      }
      if (error.message.contains('active_device_binding_required') ||
          error.message.contains('session_revoked')) {
        throw const AuthException('Active device binding required');
      }
      throw const ServerException(
        'Không thể publish encrypted vault snapshot v2.',
      );
    } on FormatException {
      throw const ServerException(
        'Encrypted vault publish v2 response có format lỗi.',
      );
    }
  }

  Future<int> rotateDeviceKeys({
    required String userId,
    required int expectedRevision,
    required int expectedKeyGeneration,
    required List<int> bindingSecretBytes,
    required EncryptedVaultEnvelope envelope,
    required WrappedVaultKey wrappedDataKey,
    required String nextVaultMembershipVerifier,
    required List<DeviceKeyRotationWrap> deviceWraps,
    required List<String> excludedDeviceKeyIds,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        rotateDeviceKeysFunctionName,
        params: <String, dynamic>{
          ...encryptedVaultPublishV2Parameters(
            expectedRevision: expectedRevision,
            expectedKeyGeneration: expectedKeyGeneration,
            bindingSecretBytes: bindingSecretBytes,
            envelope: envelope,
            wrappedDataKey: wrappedDataKey,
          ),
          'p_next_vault_membership_verifier': nextVaultMembershipVerifier,
          'p_device_wraps': deviceWraps
              .map((wrap) => wrap.toJson())
              .toList(growable: false),
          'p_excluded_device_key_ids': excludedDeviceKeyIds,
        },
      );
      if (response is! List || response.length != 1) {
        throw const FormatException('Device rotation response không hợp lệ.');
      }
      final row = response.single;
      final nextGeneration = expectedKeyGeneration + 1;
      if (row is! Map ||
          row['revision'] is! int ||
          row['key_generation'] != nextGeneration) {
        throw const FormatException('Device rotation version không hợp lệ.');
      }
      final publishedRevision = row['revision'] as int;
      if (publishedRevision != envelope.revision ||
          publishedRevision != expectedRevision + 1) {
        throw const FormatException(
          'Device rotation revision không khớp request.',
        );
      }
      return publishedRevision;
    } on PostgrestException catch (error) {
      if (isEncryptedVaultRevisionConflict(
        code: error.code,
        message: error.message,
      )) {
        throw const EncryptedVaultRevisionConflictException();
      }
      if (error.message.contains('active_device_binding_required') ||
          error.message.contains('session_revoked')) {
        throw const AuthException('Active device binding required');
      }
      throw const ServerException('Không thể rotate encrypted vault key.');
    } on FormatException {
      throw const ServerException('Device rotation response có format lỗi.');
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
