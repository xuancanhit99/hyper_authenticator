import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/device_key_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/data/models/remote_authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/authenticator_device_key.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/device_wrapped_vault_key.dart';

void main() {
  const deviceKeyId = '11111111-1111-4111-8111-111111111111';
  const installationId = '22222222-2222-4222-8222-222222222222';
  final publicKey = base64UrlEncode(List<int>.filled(32, 1));
  final proof = base64UrlEncode(List<int>.filled(32, 2));

  Map<String, dynamic> pendingRow() => <String, dynamic>{
    'device_key_id': deviceKeyId,
    'installation_id': installationId,
    'public_key': publicKey,
    'device_state': 'pending',
    'created_at': '2026-07-19T10:00:00Z',
    'wrapped_at': null,
    'activated_at': null,
    'is_current': true,
    'key_generation': null,
    'format_version': null,
    'kem': null,
    'kdf': null,
    'aead': null,
    'encapsulated_key': null,
    'ciphertext': null,
    'auth_tag': null,
    'membership_proof': null,
  };

  DeviceWrappedVaultKey wrappedKey() => DeviceWrappedVaultKey(
    formatVersion: 1,
    keyGeneration: 3,
    kem: DeviceWrappedVaultKey.kemName,
    kdf: DeviceWrappedVaultKey.kdfName,
    aead: DeviceWrappedVaultKey.aeadName,
    encapsulatedKey: base64UrlEncode(List<int>.filled(32, 3)),
    ciphertext: base64UrlEncode(List<int>.filled(32, 4)),
    authTag: base64UrlEncode(List<int>.filled(16, 5)),
  );

  test('parse pending current device không tự suy diễn wrap', () {
    final key = RemoteAuthenticatorDeviceKey.fromRow(pendingRow());

    expect(key.state, AuthenticatorDeviceKeyState.pending);
    expect(key.publicKeyBytes, List<int>.filled(32, 1));
    expect(key.wrappedVaultKey, isNull);
    expect(key.membershipProof, isNull);
    expect(key.isCurrent, isTrue);
  });

  test('parse active device chỉ khi wrap metadata đầy đủ và canonical', () {
    final envelope = wrappedKey();
    final row = <String, dynamic>{
      ...pendingRow(),
      'device_state': 'active',
      'wrapped_at': '2026-07-19T10:01:00Z',
      'activated_at': '2026-07-19T10:02:00Z',
      ...envelope.toJson(),
      'membership_proof': proof,
    };

    final key = RemoteAuthenticatorDeviceKey.fromRow(row);

    expect(key.state, AuthenticatorDeviceKeyState.active);
    expect(key.wrappedVaultKey, envelope);
    expect(key.membershipProof, proof);
    expect(key.toString(), isNot(contains(deviceKeyId)));
    expect(key.toString(), isNot(contains(envelope.ciphertext)));
    expect(key.toString(), contains('<redacted>'));
  });

  test('incomplete wrap, wrong type và state mismatch fail closed', () {
    final envelope = wrappedKey();
    final active = <String, dynamic>{
      ...pendingRow(),
      'device_state': 'active',
      'wrapped_at': '2026-07-19T10:01:00Z',
      'activated_at': '2026-07-19T10:02:00Z',
      ...envelope.toJson(),
      'membership_proof': proof,
    };

    expect(
      () => RemoteAuthenticatorDeviceKey.fromRow(<String, dynamic>{
        ...active,
        'auth_tag': null,
      }),
      throwsFormatException,
    );
    expect(
      () => RemoteAuthenticatorDeviceKey.fromRow(<String, dynamic>{
        ...active,
        'membership_proof': 123,
      }),
      throwsFormatException,
    );
    expect(
      () => RemoteAuthenticatorDeviceKey.fromRow(<String, dynamic>{
        ...active,
        'public_key': publicKey.substring(0, publicKey.length - 1),
      }),
      throwsFormatException,
    );
    expect(
      () => RemoteAuthenticatorDeviceKey.fromRow(<String, dynamic>{
        ...active,
        'device_state': 'pending',
      }),
      throwsFormatException,
    );
  });

  test('parse enrollment yêu cầu UUID, state và generation dương', () {
    final enrollment = RemoteAuthenticatorDeviceKey.enrollmentFromRow(
      <String, dynamic>{
        'device_key_id': deviceKeyId,
        'device_state': 'wrapped',
        'key_generation': 5,
      },
    );

    expect(enrollment.deviceKeyId, deviceKeyId);
    expect(enrollment.state, AuthenticatorDeviceKeyState.wrapped);
    expect(enrollment.keyGeneration, 5);
    expect(enrollment.toString(), isNot(contains(deviceKeyId)));
    expect(
      () => RemoteAuthenticatorDeviceKey.enrollmentFromRow(<String, dynamic>{
        'device_key_id': deviceKeyId,
        'device_state': 'wrapped',
        'key_generation': 0,
      }),
      throwsFormatException,
    );
  });

  test('RPC params chỉ chứa public material, binding và opaque wrap', () {
    final publicBytes = List<int>.generate(32, (index) => index);
    final bindingBytes = List<int>.generate(32, (index) => 255 - index);
    final enrollment = deviceKeyEnrollmentParameters(
      installationId: installationId,
      publicKeyBytes: publicBytes,
      bindingSecretBytes: bindingBytes,
      vaultMembershipVerifier: proof,
    );
    final wrap = deviceKeyWrapParameters(
      targetDeviceKeyId: deviceKeyId,
      bindingSecretBytes: bindingBytes,
      wrappedKey: wrappedKey(),
      vaultMembershipVerifier: proof,
      membershipProof: proof,
    );

    expect(enrollment.keys, <String>{
      'p_installation_id',
      'p_public_key',
      'p_binding_secret',
      'p_vault_membership_verifier',
    });
    expect(enrollment['p_public_key'], base64UrlEncode(publicBytes));
    expect(enrollment['p_binding_secret'], base64UrlEncode(bindingBytes));
    expect(wrap.keys, <String>{
      'p_target_device_key_id',
      'p_current_binding_secret',
      'p_expected_key_generation',
      'p_format_version',
      'p_kem',
      'p_kdf',
      'p_aead',
      'p_encapsulated_key',
      'p_ciphertext',
      'p_auth_tag',
      'p_vault_membership_verifier',
      'p_membership_proof',
    });
    expect(wrap['p_current_binding_secret'], base64UrlEncode(bindingBytes));
    expect(wrap.values, isNot(contains(publicBytes)));
  });
}
