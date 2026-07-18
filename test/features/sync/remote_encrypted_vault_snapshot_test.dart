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
      'updated_at': '2026-07-18T12:00:00Z',
    });

    expect(snapshot.envelope.revision, 3);
    expect(snapshot.wrappedDataKey.ciphertext, wrappedKey.ciphertext);
    expect(snapshot.updatedAt, DateTime.utc(2026, 7, 18, 12));
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
