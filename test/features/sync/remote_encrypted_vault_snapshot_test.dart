import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/encrypted_vault_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/data/models/remote_encrypted_vault_snapshot.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';

void main() {
  const envelope = EncryptedVaultEnvelope(
    formatVersion: 1,
    revision: 3,
    cipher: 'AES-256-GCM',
    nonce: 'AAAAAAAAAAAAAAAA',
    ciphertext: 'TEST_ONLY_CIPHERTEXT',
    authTag: 'AAAAAAAAAAAAAAAAAAAAAA==',
  );
  const wrappedKey = WrappedVaultKey(
    formatVersion: 1,
    cipher: 'AES-256-GCM',
    nonce: 'BBBBBBBBBBBBBBBB',
    ciphertext: 'TEST_ONLY_WRAPPED_KEY_CIPHERTEXT_1234567890',
    authTag: 'BBBBBBBBBBBBBBBBBBBBBB==',
  );

  test('mapper đọc encrypted row mà không cần plaintext account field', () {
    final snapshot = RemoteEncryptedVaultSnapshot.fromRow(<String, dynamic>{
      ...envelope.toJson(),
      'key_format_version': wrappedKey.formatVersion,
      'wrapped_key_nonce': wrappedKey.nonce,
      'wrapped_key_ciphertext': wrappedKey.ciphertext,
      'wrapped_key_auth_tag': wrappedKey.authTag,
      'key_generation': 4,
      'device_wrap_version': 1,
      'updated_at': '2026-07-18T12:00:00Z',
    });

    expect(snapshot.envelope.revision, 3);
    expect(snapshot.wrappedDataKey.ciphertext, wrappedKey.ciphertext);
    expect(snapshot.updatedAt, DateTime.utc(2026, 7, 18, 12));
    expect(snapshot.keyGeneration, 4);
    expect(snapshot.deviceWrapVersion, 1);
  });

  test(
    'publish params chỉ chứa encrypted envelope và concurrency metadata',
    () {
      final params = encryptedVaultPublishParameters(
        expectedRevision: 2,
        envelope: envelope,
        wrappedDataKey: wrappedKey,
      );
      final serialized = jsonEncode(params);

      expect(params['p_expected_revision'], 2);
      expect(serialized, isNot(contains('secret_key')));
      expect(serialized, isNot(contains('account_name')));
      expect(serialized, isNot(contains('issuer')));
    },
  );

  test('publish v2 bind exact generation và device binding secret', () {
    final bindingSecret = List<int>.generate(32, (index) => index);
    final params = encryptedVaultPublishV2Parameters(
      expectedRevision: 2,
      expectedKeyGeneration: 4,
      bindingSecretBytes: bindingSecret,
      envelope: envelope,
      wrappedDataKey: wrappedKey,
    );

    expect(params['p_expected_revision'], 2);
    expect(params['p_expected_key_generation'], 4);
    expect(params['p_current_binding_secret'], base64UrlEncode(bindingSecret));
    expect(jsonEncode(params), isNot(contains('private_key')));
  });

  test('snapshot generation/protocol ngoài contract fail closed', () {
    Map<String, dynamic> row() => <String, dynamic>{
      ...envelope.toJson(),
      'key_format_version': wrappedKey.formatVersion,
      'wrapped_key_nonce': wrappedKey.nonce,
      'wrapped_key_ciphertext': wrappedKey.ciphertext,
      'wrapped_key_auth_tag': wrappedKey.authTag,
      'key_generation': 1,
      'device_wrap_version': 0,
      'updated_at': '2026-07-18T12:00:00Z',
    };

    expect(
      () => RemoteEncryptedVaultSnapshot.fromRow(<String, dynamic>{
        ...row(),
        'key_generation': 0,
      }),
      throwsFormatException,
    );
    expect(
      () => RemoteEncryptedVaultSnapshot.fromRow(<String, dynamic>{
        ...row(),
        'device_wrap_version': 2,
      }),
      throwsFormatException,
    );
  });

  test('PT409 được nhận diện là optimistic revision conflict', () {
    expect(
      isEncryptedVaultRevisionConflict(
        code: 'PT409',
        message: 'revision_conflict',
      ),
      isTrue,
    );
    expect(
      isEncryptedVaultRevisionConflict(
        code: '42501',
        message: 'permission denied',
      ),
      isFalse,
    );
  });
}
