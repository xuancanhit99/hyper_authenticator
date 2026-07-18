import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/encrypted_vault_envelope.dart';
import 'package:hyper_authenticator/features/sync/domain/services/vault_cipher.dart';

void main() {
  late VaultCipher cipher;
  late VaultKeyBundle keyBundle;

  const account = AuthenticatorAccount(
    id: '11111111-1111-4111-8111-111111111111',
    issuer: 'TEST_ONLY Issuer',
    accountName: 'user@example.invalid',
    secretKey: 'JBSWY3DPEHPK3PXP',
    algorithm: 'SHA256',
    digits: 8,
    period: 45,
  );

  setUp(() async {
    cipher = VaultCipher();
    keyBundle = await cipher.createKeyBundle(userId: 'TEST_ONLY_USER_A');
  });

  test('round-trip encrypted snapshot giữ đủ TOTP field', () async {
    final envelope = await cipher.encryptAccounts(
      accounts: const [account],
      dataKeyBytes: keyBundle.dataKeyBytes,
      userId: 'TEST_ONLY_USER_A',
      revision: 1,
    );
    final decrypted = await cipher.decryptAccounts(
      envelope: envelope,
      dataKeyBytes: keyBundle.dataKeyBytes,
      userId: 'TEST_ONLY_USER_A',
    );

    expect(decrypted, const [account]);
    final serialized = jsonEncode(envelope.toJson());
    expect(serialized, isNot(contains(account.secretKey)));
    expect(serialized, isNot(contains(account.issuer)));
    expect(serialized, isNot(contains(account.accountName)));
  });

  test('tamper ciphertext hoặc đổi user làm authentication thất bại', () async {
    final envelope = await cipher.encryptAccounts(
      accounts: const [account],
      dataKeyBytes: keyBundle.dataKeyBytes,
      userId: 'TEST_ONLY_USER_A',
      revision: 7,
    );
    final bytes = base64Url.decode(envelope.ciphertext);
    bytes[0] ^= 1;
    final tampered = EncryptedVaultEnvelope(
      formatVersion: envelope.formatVersion,
      revision: envelope.revision,
      cipher: envelope.cipher,
      nonce: envelope.nonce,
      ciphertext: base64UrlEncode(bytes),
      authTag: envelope.authTag,
    );

    await expectLater(
      cipher.decryptAccounts(
        envelope: tampered,
        dataKeyBytes: keyBundle.dataKeyBytes,
        userId: 'TEST_ONLY_USER_A',
      ),
      throwsA(isA<VaultCryptoException>()),
    );
    await expectLater(
      cipher.decryptAccounts(
        envelope: envelope,
        dataKeyBytes: keyBundle.dataKeyBytes,
        userId: 'TEST_ONLY_USER_B',
      ),
      throwsA(isA<VaultCryptoException>()),
    );
  });

  test('recovery key unwrap đúng DEK và fail với sai user', () async {
    final recovered = await cipher.unwrapDataKey(
      wrappedKey: keyBundle.wrappedDataKey,
      recoveryCode: keyBundle.recoveryCode,
      userId: 'TEST_ONLY_USER_A',
    );

    expect(recovered, keyBundle.dataKeyBytes);
    expect(keyBundle.recoveryCode, startsWith('HA1-'));
    await expectLater(
      cipher.unwrapDataKey(
        wrappedKey: keyBundle.wrappedDataKey,
        recoveryCode: keyBundle.recoveryCode,
        userId: 'TEST_ONLY_USER_B',
      ),
      throwsA(isA<VaultCryptoException>()),
    );
  });

  test('future envelope version bị từ chối trước khi decrypt', () async {
    final envelope = await cipher.encryptAccounts(
      accounts: const [account],
      dataKeyBytes: keyBundle.dataKeyBytes,
      userId: 'TEST_ONLY_USER_A',
      revision: 1,
    );
    final future = EncryptedVaultEnvelope(
      formatVersion: 999,
      revision: envelope.revision,
      cipher: envelope.cipher,
      nonce: envelope.nonce,
      ciphertext: envelope.ciphertext,
      authTag: envelope.authTag,
    );

    await expectLater(
      cipher.decryptAccounts(
        envelope: future,
        dataKeyBytes: keyBundle.dataKeyBytes,
        userId: 'TEST_ONLY_USER_A',
      ),
      throwsA(isA<VaultCryptoException>()),
    );
  });
}
