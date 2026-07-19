import 'dart:convert';

import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/sync/data/models/remote_authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceKeyConflictException implements Exception {
  const DeviceKeyConflictException();
}

class DeviceKeyBindingException implements Exception {
  const DeviceKeyBindingException();
}

Map<String, dynamic> deviceKeyEnrollmentParameters({
  required String installationId,
  required List<int> publicKeyBytes,
  required List<int> bindingSecretBytes,
  required String vaultMembershipVerifier,
}) => <String, dynamic>{
  'p_installation_id': installationId,
  'p_public_key': base64UrlEncode(publicKeyBytes),
  'p_binding_secret': base64UrlEncode(bindingSecretBytes),
  'p_vault_membership_verifier': vaultMembershipVerifier,
};

Map<String, dynamic> deviceKeyWrapParameters({
  required String targetDeviceKeyId,
  required List<int> bindingSecretBytes,
  required DeviceWrappedVaultKey wrappedKey,
  required String vaultMembershipVerifier,
  required String membershipProof,
}) => <String, dynamic>{
  'p_target_device_key_id': targetDeviceKeyId,
  'p_current_binding_secret': base64UrlEncode(bindingSecretBytes),
  'p_expected_key_generation': wrappedKey.keyGeneration,
  'p_format_version': wrappedKey.formatVersion,
  'p_kem': wrappedKey.kem,
  'p_kdf': wrappedKey.kdf,
  'p_aead': wrappedKey.aead,
  'p_encapsulated_key': wrappedKey.encapsulatedKey,
  'p_ciphertext': wrappedKey.ciphertext,
  'p_auth_tag': wrappedKey.authTag,
  'p_vault_membership_verifier': vaultMembershipVerifier,
  'p_membership_proof': membershipProof,
};

@lazySingleton
class DeviceKeyRemoteDataSource {
  static const beginFunctionName = 'begin_authenticator_device_key_enrollment';
  static const listFunctionName = 'list_authenticator_device_keys';
  static const publishWrapFunctionName =
      'publish_authenticator_device_key_wrap';
  static const confirmFunctionName = 'confirm_current_authenticator_device_key';

  final SupabaseClient _client;

  DeviceKeyRemoteDataSource(this._client);

  Future<DeviceKeyEnrollment> beginEnrollment({
    required String userId,
    required String installationId,
    required List<int> publicKeyBytes,
    required List<int> bindingSecretBytes,
    required String vaultMembershipVerifier,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        beginFunctionName,
        params: deviceKeyEnrollmentParameters(
          installationId: installationId,
          publicKeyBytes: publicKeyBytes,
          bindingSecretBytes: bindingSecretBytes,
          vaultMembershipVerifier: vaultMembershipVerifier,
        ),
      );
      final row = _singleRow(response, 'Device key enrollment response lỗi.');
      return RemoteAuthenticatorDeviceKey.enrollmentFromRow(row);
    } on PostgrestException catch (error) {
      _mapPostgrest(error);
    } on FormatException {
      throw const ServerException('Device key enrollment response lỗi.');
    }
  }

  Future<List<AuthenticatorDeviceKey>> list({required String userId}) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(listFunctionName);
      if (response is! List) {
        throw const FormatException('Device key list response lỗi.');
      }
      final keys = response
          .map((row) {
            if (row is! Map) {
              throw const FormatException('Device key list row lỗi.');
            }
            return RemoteAuthenticatorDeviceKey.fromRow(
              Map<String, dynamic>.from(row),
            );
          })
          .toList(growable: false);
      if (keys.where((key) => key.isCurrent).length != 1) {
        throw const FormatException(
          'Device key list thiếu current device duy nhất.',
        );
      }
      return keys;
    } on PostgrestException catch (error) {
      _mapPostgrest(error);
    } on FormatException {
      throw const ServerException('Device key list response lỗi.');
    }
  }

  Future<void> publishWrap({
    required String userId,
    required String targetDeviceKeyId,
    required List<int> bindingSecretBytes,
    required DeviceWrappedVaultKey wrappedKey,
    required String vaultMembershipVerifier,
    required String membershipProof,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        publishWrapFunctionName,
        params: deviceKeyWrapParameters(
          targetDeviceKeyId: targetDeviceKeyId,
          bindingSecretBytes: bindingSecretBytes,
          wrappedKey: wrappedKey,
          vaultMembershipVerifier: vaultMembershipVerifier,
          membershipProof: membershipProof,
        ),
      );
      if (response != true) {
        throw const FormatException('Device wrap response lỗi.');
      }
    } on PostgrestException catch (error) {
      _mapPostgrest(error);
    } on FormatException {
      throw const ServerException('Server không xác nhận device wrap.');
    }
  }

  Future<void> confirmCurrent({
    required String userId,
    required String deviceKeyId,
    required List<int> bindingSecretBytes,
    required int keyGeneration,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        confirmFunctionName,
        params: <String, dynamic>{
          'p_device_key_id': deviceKeyId,
          'p_binding_secret': base64UrlEncode(bindingSecretBytes),
          'p_expected_key_generation': keyGeneration,
        },
      );
      if (response != true) {
        throw const FormatException('Device key confirmation response lỗi.');
      }
    } on PostgrestException catch (error) {
      _mapPostgrest(error);
    } on FormatException {
      throw const ServerException('Server không xác nhận device key.');
    }
  }

  Map<String, dynamic> _singleRow(dynamic response, String message) {
    if (response is! List || response.length != 1 || response.single is! Map) {
      throw FormatException(message);
    }
    return Map<String, dynamic>.from(response.single as Map);
  }

  Never _mapPostgrest(PostgrestException error) {
    if (error.code == 'PT409' || error.message.contains('conflict')) {
      throw const DeviceKeyConflictException();
    }
    if (error.message.contains('binding_required') ||
        error.message.contains('trusted_source_device_required') ||
        error.message.contains('vault_membership_verifier') ||
        error.message.contains('device_key_recovery_proof_invalid') ||
        error.message.contains('verified_current_device_wrap_required') ||
        error.message.contains('session_revoked')) {
      throw const DeviceKeyBindingException();
    }
    throw const ServerException('Device key operation thất bại an toàn.');
  }

  void _requireAuthenticatedUser(String expectedUserId) {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('User not logged in');
    }
    if (currentUser.id != expectedUserId) {
      throw const AuthException('Authenticated user changed during operation');
    }
  }
}
