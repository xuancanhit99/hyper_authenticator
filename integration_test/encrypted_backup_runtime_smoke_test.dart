import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/security/privacy_shield.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/encrypted_backup_file_gateway.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/encrypted_backup_file_codec.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:hyper_authenticator/injection_container.dart' as di;
import 'package:hyper_authenticator/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _allowVaultReset = bool.fromEnvironment('ALLOW_DEVICE_TEST_VAULT_RESET');
const _smokePhase = String.fromEnvironment('ENCRYPTED_BACKUP_SMOKE_PHASE');
const _testPassword = 'TEST_ONLY-backup-password-2026';
const _tamperedFileName = 'hyper-authenticator-test-tampered.hyauth';
const _testAccounts = <AuthenticatorAccount>[
  AuthenticatorAccount(
    id: '00000000-0000-4000-8000-000000000101',
    issuer: 'TEST_ONLY Backup Runtime',
    accountName: 'runtime-one@example.invalid',
    secretKey: 'JBSWY3DPEHPK3PXP',
    algorithm: 'SHA512',
    digits: 8,
    period: 45,
  ),
  AuthenticatorAccount(
    id: '00000000-0000-4000-8000-000000000102',
    issuer: 'TEST_ONLY Backup Runtime',
    accountName: 'runtime-two@example.invalid',
    secretKey: 'JBSWY3DPEHPK3PXP',
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'encrypted backup runtime smoke phase $_smokePhase',
    (tester) async {
      _runtimePhase('start');
      expect(
        _allowVaultReset,
        isTrue,
        reason:
            'Test này xóa local vault trên target. Chỉ chạy qua guarded device harness.',
      );
      expect(
        _smokePhase,
        anyOf('export', 'restore'),
        reason: 'Phase phải là export hoặc restore.',
      );

      final preferences = await SharedPreferences.getInstance();
      FlutterSecureStorage? secureStorage;
      AuthenticatorRepository? repository;

      try {
        await preferences.setBool('biometric_enabled', false);
        await app.main();
        await _pumpUntil(tester, find.byTooltip('Thêm tài khoản'));
        _runtimePhase('bootstrap-ready');

        secureStorage = di.sl<FlutterSecureStorage>();
        repository = di.sl<AuthenticatorRepository>();
        final accountsBloc = di.sl<AccountsBloc>();
        await _replaceVault(repository, const []);
        accountsBloc.add(LoadAccounts());
        await _pumpUntil(
          tester,
          find.text('Không tìm thấy tài khoản phù hợp.'),
        );
        _runtimePhase('clean-vault-ready');

        await tester.tap(find.byKey(MainNavigationPage.settingsTabKey).last);
        await _pumpUntil(tester, find.text('Cài đặt'));
        await tester.tap(
          find.byKey(const Key('encrypted-backup-file-settings')),
        );
        await _pumpUntil(tester, find.text('Backup file mã hóa'));

        if (_smokePhase == 'export') {
          await _runExportPhase(
            tester: tester,
            repository: repository,
            accountsBloc: accountsBloc,
          );
        } else {
          await _runRestorePhase(tester: tester, repository: repository);
        }
      } finally {
        try {
          if (repository != null) {
            await _replaceVault(repository, const []);
          }
        } finally {
          try {
            await secureStorage?.deleteAll();
          } finally {
            await preferences.clear();
          }
        }
        _runtimePhase('finally-cleanup-complete');
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _runExportPhase({
  required WidgetTester tester,
  required AuthenticatorRepository repository,
  required AccountsBloc accountsBloc,
}) async {
  await _replaceVault(repository, _testAccounts);
  accountsBloc.add(LoadAccounts());
  expect(await _readVault(repository), _testAccounts);
  _runtimePhase('fixture-seeded');

  await _openExportPassword(tester);
  _runtimePhase('awaiting-share-cancel');
  await tester.tap(find.byKey(const Key('submit-backup-password')));
  await _pumpUntil(
    tester,
    find.textContaining('hủy vị trí lưu'),
    timeout: const Duration(minutes: 5),
  );
  expect(await _readVault(repository), _testAccounts);
  _runtimePhase('share-cancel-verified');

  await _openExportPassword(tester);
  _runtimePhase('awaiting-valid-system-save');
  await tester.tap(find.byKey(const Key('submit-backup-password')));
  await _pumpUntil(
    tester,
    find.textContaining('Đã tạo file backup'),
    timeout: const Duration(minutes: 5),
  );
  expect(await _readVault(repository), _testAccounts);
  _runtimePhase('valid-system-save-verified');

  final codec = di.sl<EncryptedBackupFileCodec>();
  final gateway = di.sl<EncryptedBackupFileGateway>();
  final encoded = await codec.encrypt(
    accounts: _testAccounts,
    password: _testPassword,
  );
  final tampered = _tamperCiphertext(encoded);
  encoded.fillRange(0, encoded.length, 0);
  try {
    _runtimePhase('awaiting-tampered-system-save');
    final result = await gateway.saveBackup(
      bytes: tampered,
      suggestedName: _tamperedFileName,
    );
    expect(result, BackupFileSaveResult.saved);
    _runtimePhase('tampered-system-save-verified');
  } finally {
    tampered.fillRange(0, tampered.length, 0);
  }

  await _replaceVault(repository, const []);
  accountsBloc.add(LoadAccounts());
  expect(await _readVault(repository), isEmpty);
  _runtimePhase('clean-vault-after-export-verified');
}

Future<void> _runRestorePhase({
  required WidgetTester tester,
  required AuthenticatorRepository repository,
}) async {
  await _pickAndSubmitPassword(
    tester,
    phase: 'awaiting-tampered-system-pick',
    password: _testPassword,
  );
  await _pumpUntil(tester, find.textContaining('file backup đã bị thay đổi'));
  expect(await _readVault(repository), isEmpty);
  _runtimePhase('tampered-file-rejected');

  await _pickAndSubmitPassword(
    tester,
    phase: 'awaiting-valid-system-pick-for-wrong-password',
    password: 'TEST_ONLY-wrong-password-2026',
  );
  await _pumpUntil(tester, find.textContaining('Sai mật khẩu'));
  expect(await _readVault(repository), isEmpty);
  _runtimePhase('wrong-password-rejected');

  await _pickAndSubmitPassword(
    tester,
    phase: 'awaiting-valid-system-pick-for-cancel-preview',
    password: _testPassword,
  );
  await _pumpUntil(tester, find.text('Thay toàn bộ local vault?'));
  expect(find.text('TEST_ONLY Backup Runtime'), findsNWidgets(2));
  await tester.tap(find.text('Giữ vault hiện tại'));
  await _pumpUntil(tester, find.textContaining('Đã hủy import'));
  expect(await _readVault(repository), isEmpty);
  _runtimePhase('preview-cancel-verified');

  await _pickAndSubmitPassword(
    tester,
    phase: 'awaiting-valid-system-pick-for-restore',
    password: _testPassword,
  );
  await _pumpUntil(tester, find.text('Thay toàn bộ local vault?'));
  await tester.enterText(
    find.byKey(const Key('restore-confirmation-phrase')),
    'KHOI PHUC',
  );
  await tester.pump();
  final restoreButton = find.byKey(const Key('confirm-atomic-restore'));
  expect(tester.widget<FilledButton>(restoreButton).onPressed, isNotNull);
  await tester.tap(restoreButton);
  await _pumpUntil(tester, find.textContaining('Khôi phục hoàn tất'));

  final restored = await _readVault(repository);
  expect(restored, _testAccounts);
  _runtimePhase('atomic-restore-verified');
}

Future<void> _openExportPassword(WidgetTester tester) async {
  final createBackup = find.byKey(const Key('create-encrypted-backup'));
  final passwordPrompt = find.text('Đặt password cho backup');
  for (var attempt = 0; attempt < 3; attempt++) {
    if (createBackup.evaluate().isNotEmpty) {
      await tester.pump(const Duration(seconds: 1));
      if (createBackup.evaluate().isEmpty) continue;
      await tester.tap(createBackup);
      await _pumpUntil(tester, passwordPrompt);
      break;
    }

    final backupSettings = find.byKey(
      const Key('encrypted-backup-file-settings'),
    );
    await _pumpUntil(
      tester,
      backupSettings,
      timeout: const Duration(minutes: 1),
    );
    await tester.pump(const Duration(seconds: 1));
    if (backupSettings.evaluate().isEmpty) continue;
    await tester.tap(backupSettings);
    await _pumpUntil(tester, createBackup, timeout: const Duration(minutes: 1));
  }
  expect(passwordPrompt, findsOneWidget);
  await tester.enterText(
    find.byKey(const Key('backup-password')),
    _testPassword,
  );
  await tester.enterText(
    find.byKey(const Key('backup-password-confirmation')),
    _testPassword,
  );
}

Future<void> _pickAndSubmitPassword(
  WidgetTester tester, {
  required String phase,
  required String password,
}) async {
  _runtimePhase(phase);
  await tester.tap(find.byKey(const Key('pick-encrypted-backup')));
  await _pumpUntil(
    tester,
    find.text('Mở file backup'),
    timeout: const Duration(minutes: 5),
  );
  await _pumpUntilAppResumed(tester);
  await tester.enterText(find.byKey(const Key('backup-password')), password);
  await tester.pump();
  await tester.tap(find.byKey(const Key('submit-backup-password')));
}

Uint8List _tamperCiphertext(Uint8List encoded) {
  final decoded = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;
  final cipher = decoded['cipher'] as Map<String, dynamic>;
  final ciphertext = cipher['ciphertext'] as String;
  cipher['ciphertext'] =
      '${ciphertext.startsWith('A') ? 'B' : 'A'}${ciphertext.substring(1)}';
  return Uint8List.fromList(utf8.encode(jsonEncode(decoded)));
}

Future<List<AuthenticatorAccount>> _readVault(
  AuthenticatorRepository repository,
) async {
  final result = await repository.getAccounts();
  return result.fold(
    (failure) => throw TestFailure(
      'Không đọc được test vault (${failure.runtimeType}).',
    ),
    (accounts) => accounts,
  );
}

Future<void> _replaceVault(
  AuthenticatorRepository repository,
  List<AuthenticatorAccount> accounts,
) async {
  final result = await repository.replaceAccounts(accounts);
  result.fold(
    (failure) => throw TestFailure(
      'Không reset được test vault (${failure.runtimeType}).',
    ),
    (_) {},
  );
}

void _runtimePhase(String name) {
  debugPrint('ENCRYPTED_BACKUP_DEVICE_PHASE=$name');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timeout khi chờ widget: $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _pumpUntilAppResumed(WidgetTester tester) async {
  final privacyShield = find.byKey(privacyShieldOverlayKey);
  final deadline = DateTime.now().add(const Duration(minutes: 1));
  while (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
      privacyShield.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timeout khi chờ ứng dụng trở lại foreground.');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 500));
}
