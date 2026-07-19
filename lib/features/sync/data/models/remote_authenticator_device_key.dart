import 'dart:convert';
import 'dart:typed_data';

import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';
import 'package:uuid/uuid.dart';

class RemoteAuthenticatorDeviceKey {
  static AuthenticatorDeviceKey fromRow(Map<String, dynamic> row) {
    final deviceKeyId = row['device_key_id'];
    final installationId = row['installation_id'];
    final publicKey = row['public_key'];
    final stateValue = row['device_state'];
    final createdAtValue = row['created_at'];
    final wrappedAtValue = row['wrapped_at'];
    final activatedAtValue = row['activated_at'];
    final isCurrent = row['is_current'];
    if (deviceKeyId is! String ||
        !Uuid.isValidUUID(fromString: deviceKeyId) ||
        installationId is! String ||
        !Uuid.isValidUUID(fromString: installationId) ||
        publicKey is! String ||
        stateValue is! String ||
        createdAtValue is! String ||
        isCurrent is! bool) {
      throw const FormatException('Device key row không hợp lệ.');
    }
    final state = _parseState(stateValue);
    final createdAt = DateTime.tryParse(createdAtValue)?.toUtc();
    final wrappedAt = _optionalTimestamp(wrappedAtValue);
    final activatedAt = _optionalTimestamp(activatedAtValue);
    final publicKeyBytes = _decodeCanonical(publicKey, 32);
    if (createdAt == null ||
        (wrappedAt != null && wrappedAt.isBefore(createdAt)) ||
        (activatedAt != null &&
            (wrappedAt == null || activatedAt.isBefore(wrappedAt)))) {
      throw const FormatException('Device key timestamp không hợp lệ.');
    }

    final wrapValues = <dynamic>[
      row['key_generation'],
      row['format_version'],
      row['kem'],
      row['kdf'],
      row['aead'],
      row['encapsulated_key'],
      row['ciphertext'],
      row['auth_tag'],
      row['membership_proof'],
    ];
    final hasAnyWrapValue = wrapValues.any((value) => value != null);
    final hasAllWrapValues = wrapValues.every((value) => value != null);
    if (hasAnyWrapValue != hasAllWrapValues) {
      throw const FormatException('Device wrap row không đầy đủ.');
    }

    DeviceWrappedVaultKey? wrappedVaultKey;
    String? membershipProof;
    if (hasAllWrapValues) {
      if (row['membership_proof'] is! String) {
        throw const FormatException('Device membership proof không hợp lệ.');
      }
      membershipProof = row['membership_proof'] as String;
      _decodeCanonical(membershipProof, 32);
      wrappedVaultKey = DeviceWrappedVaultKey.fromJson(<String, dynamic>{
        'format_version': row['format_version'],
        'key_generation': row['key_generation'],
        'kem': row['kem'],
        'kdf': row['kdf'],
        'aead': row['aead'],
        'encapsulated_key': row['encapsulated_key'],
        'ciphertext': row['ciphertext'],
        'auth_tag': row['auth_tag'],
      });
    }
    if ((state == AuthenticatorDeviceKeyState.pending && hasAnyWrapValue) ||
        (state != AuthenticatorDeviceKeyState.pending && !hasAllWrapValues) ||
        (state == AuthenticatorDeviceKeyState.pending && wrappedAt != null) ||
        (state == AuthenticatorDeviceKeyState.wrapped &&
            (wrappedAt == null || activatedAt != null)) ||
        (state == AuthenticatorDeviceKeyState.active &&
            (wrappedAt == null || activatedAt == null))) {
      throw const FormatException('Device key state không khớp wrap metadata.');
    }

    return AuthenticatorDeviceKey(
      deviceKeyId: deviceKeyId,
      installationId: installationId,
      publicKeyBytes: publicKeyBytes,
      state: state,
      createdAt: createdAt,
      wrappedAt: wrappedAt,
      activatedAt: activatedAt,
      isCurrent: isCurrent,
      wrappedVaultKey: wrappedVaultKey,
      membershipProof: membershipProof,
    );
  }

  static DeviceKeyEnrollment enrollmentFromRow(Map<String, dynamic> row) {
    final deviceKeyId = row['device_key_id'];
    final stateValue = row['device_state'];
    final keyGeneration = row['key_generation'];
    if (deviceKeyId is! String ||
        !Uuid.isValidUUID(fromString: deviceKeyId) ||
        stateValue is! String ||
        keyGeneration is! int ||
        keyGeneration < 1) {
      throw const FormatException('Device key enrollment response lỗi.');
    }
    return DeviceKeyEnrollment(
      deviceKeyId: deviceKeyId,
      state: _parseState(stateValue),
      keyGeneration: keyGeneration,
    );
  }

  static AuthenticatorDeviceKeyState _parseState(String value) =>
      switch (value) {
        'pending' => AuthenticatorDeviceKeyState.pending,
        'wrapped' => AuthenticatorDeviceKeyState.wrapped,
        'active' => AuthenticatorDeviceKeyState.active,
        _ => throw const FormatException('Device key state không hỗ trợ.'),
      };

  static DateTime? _optionalTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Device key timestamp không hợp lệ.');
    }
    final timestamp = DateTime.tryParse(value)?.toUtc();
    if (timestamp == null) {
      throw const FormatException('Device key timestamp không hợp lệ.');
    }
    return timestamp;
  }

  static Uint8List _decodeCanonical(String value, int length) {
    final expectedEncodedLength = ((length + 2) ~/ 3) * 4;
    if (value.length != expectedEncodedLength) {
      throw const FormatException('Device key encoding không hợp lệ.');
    }
    try {
      final decoded = base64Url.decode(value);
      if (decoded.length != length || base64UrlEncode(decoded) != value) {
        throw const FormatException('Device key encoding không canonical.');
      }
      return Uint8List.fromList(decoded);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Device key encoding không hợp lệ.');
    }
  }
}
