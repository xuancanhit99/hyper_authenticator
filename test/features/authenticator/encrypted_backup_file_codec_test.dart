import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/encrypted_backup_file_codec.dart';

void main() {
  late EncryptedBackupFileCodec codec;

  setUp(() {
    codec = EncryptedBackupFileCodec.forTesting(
      memoryKiB: 32,
      iterations: 1,
      randomBytes: (int length) =>
          List<int>.generate(length, (index) => (index * 17 + length) & 0xff),
      now: () => DateTime.utc(2026, 7, 27, 10, 30),
    );
  });

  test('round-trip v1 giữ nguyên stable ID, order và TOTP semantics', () async {
    final accounts = <AuthenticatorAccount>[
      const AuthenticatorAccount(
        id: '00000000-0000-4000-8000-000000000002',
        issuer: 'Dịch vụ α',
        accountName: 'user+hai@example.invalid',
        secretKey: 'JBSWY3DPEHPK3PXP',
        algorithm: 'SHA512',
        digits: 8,
        period: 45,
      ),
      const AuthenticatorAccount(
        id: '00000000-0000-4000-8000-000000000001',
        issuer: 'Service',
        accountName: 'first@example.invalid',
        secretKey: 'JBSWY3DPEHPK3PXP',
      ),
    ];

    final encoded = await codec.encrypt(
      accounts: accounts,
      password: 'TEST_ONLY-password-1',
    );
    final decoded = await codec.decrypt(
      fileBytes: encoded,
      password: 'TEST_ONLY-password-1',
    );

    expect(decoded.formatVersion, 1);
    expect(decoded.createdAt, DateTime.utc(2026, 7, 27, 10, 30));
    expect(decoded.accounts, accounts);
    expect(decoded.toString(), isNot(contains(accounts.first.secretKey)));

    final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    expect(envelope['format'], 'hyper-authenticator-encrypted-backup');
    expect(envelope['format_version'], 1);
    expect(envelope['kdf'], {
      'name': 'argon2id',
      'version': 19,
      'memory_kib': 32,
      'iterations': 1,
      'parallelism': 1,
      'salt': isA<String>(),
    });
    expect((envelope['cipher'] as Map<String, dynamic>)['name'], 'aes-256-gcm');
  });

  test(
    'wrong password và ciphertext tamper trả cùng integrity failure',
    () async {
      final encoded = await codec.encrypt(
        accounts: [_account()],
        password: 'TEST_ONLY-password-1',
      );

      await expectLater(
        codec.decrypt(fileBytes: encoded, password: 'TEST_ONLY-password-2'),
        throwsA(isA<BackupIntegrityException>()),
      );

      final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      final cipher = envelope['cipher'] as Map<String, dynamic>;
      final ciphertext = cipher['ciphertext'] as String;
      final padding = '=' * ((4 - ciphertext.length % 4) % 4);
      final tamperedCiphertext = base64Url.decode('$ciphertext$padding');
      tamperedCiphertext[0] ^= 1;
      cipher['ciphertext'] = base64UrlEncode(
        tamperedCiphertext,
      ).replaceAll('=', '');
      final tampered = utf8.encode(jsonEncode(envelope));

      await expectLater(
        codec.decrypt(fileBytes: tampered, password: 'TEST_ONLY-password-1'),
        throwsA(isA<BackupIntegrityException>()),
      );
    },
  );

  test('header tamper bị AAD authentication từ chối', () async {
    final encoded = await codec.encrypt(
      accounts: [_account()],
      password: 'TEST_ONLY-password-1',
    );
    final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
    final kdf = envelope['kdf'] as Map<String, dynamic>;
    kdf['parallelism'] = 2;

    await expectLater(
      codec.decrypt(
        fileBytes: utf8.encode(jsonEncode(envelope)),
        password: 'TEST_ONLY-password-1',
      ),
      throwsA(isA<BackupIntegrityException>()),
    );
  });

  test(
    'future version và KDF ngoài resource bound fail trước decrypt',
    () async {
      final encoded = await codec.encrypt(
        accounts: [_account()],
        password: 'TEST_ONLY-password-1',
      );
      final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      envelope['format_version'] = 2;

      await expectLater(
        codec.decrypt(
          fileBytes: utf8.encode(jsonEncode(envelope)),
          password: 'TEST_ONLY-password-1',
        ),
        throwsA(isA<BackupFormatException>()),
      );

      envelope['format_version'] = 1;
      final kdf = envelope['kdf'] as Map<String, dynamic>;
      kdf['memory_kib'] = EncryptedBackupFileCodec.maximumMemoryKiB + 1;
      await expectLater(
        codec.decrypt(
          fileBytes: utf8.encode(jsonEncode(envelope)),
          password: 'TEST_ONLY-password-1',
        ),
        throwsA(isA<BackupFormatException>()),
      );
    },
  );

  test('non-canonical JSON và duplicate stable ID bị từ chối', () async {
    final encoded = await codec.encrypt(
      accounts: [_account()],
      password: 'TEST_ONLY-password-1',
    );
    await expectLater(
      codec.decrypt(
        fileBytes: utf8.encode(' ${utf8.decode(encoded)}'),
        password: 'TEST_ONLY-password-1',
      ),
      throwsA(isA<BackupFormatException>()),
    );

    await expectLater(
      codec.encrypt(
        accounts: [_account(), _account()],
        password: 'TEST_ONLY-password-1',
      ),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('password policy và file size bound fail closed', () async {
    await expectLater(
      codec.encrypt(accounts: [_account()], password: 'short'),
      throwsA(isA<BackupPasswordException>()),
    );
    await expectLater(
      codec.decrypt(
        fileBytes: List<int>.filled(
          EncryptedBackupFileCodec.maximumFileBytes + 1,
          0,
        ),
        password: 'TEST_ONLY-password-1',
      ),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test(
    'production encoder pin OWASP Argon2id parameters và tự decrypt được',
    () async {
      final productionCodec = EncryptedBackupFileCodec();
      final encoded = await productionCodec.encrypt(
        accounts: const [],
        password: 'TEST_ONLY-production-password',
      );
      final envelope = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
      expect(envelope['kdf'], {
        'name': 'argon2id',
        'version': 19,
        'memory_kib': EncryptedBackupFileCodec.defaultMemoryKiB,
        'iterations': EncryptedBackupFileCodec.defaultIterations,
        'parallelism': EncryptedBackupFileCodec.defaultParallelism,
        'salt': isA<String>(),
      });

      final decoded = await productionCodec.decrypt(
        fileBytes: encoded,
        password: 'TEST_ONLY-production-password',
      );
      expect(decoded.accounts, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

AuthenticatorAccount _account() => const AuthenticatorAccount(
  id: '00000000-0000-4000-8000-000000000001',
  issuer: 'TEST_ONLY Service',
  accountName: 'user@example.invalid',
  secretKey: 'JBSWY3DPEHPK3PXP',
  algorithm: 'SHA256',
  digits: 7,
  period: 60,
);
