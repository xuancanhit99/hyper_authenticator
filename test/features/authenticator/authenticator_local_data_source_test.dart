import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/data/datasources/authenticator_local_data_source.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:uuid/uuid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemorySecureStorage storage;
  late AuthenticatorLocalDataSourceImpl dataSource;

  setUp(() {
    storage = _MemorySecureStorage();
    dataSource = AuthenticatorLocalDataSourceImpl(
      secureStorage: storage,
      uuid: const Uuid(),
    );
  });

  test(
    'migrate legacy record, recover orphan và không xóa dữ liệu v1',
    () async {
      final indexed = _account(
        id: '00000000-0000-4000-8000-000000000001',
        issuer: 'Indexed',
      );
      final orphan = _account(
        id: '00000000-0000-4000-8000-000000000002',
        issuer: 'Orphan',
      );
      storage.values.addAll(<String, String>{
        'authenticator_account_index': jsonEncode(<String>[indexed.id]),
        indexed.id: jsonEncode(indexed.toJson()),
        orphan.id: jsonEncode(orphan.toJson()),
      });

      final migrated = await dataSource.getAccounts();

      expect(migrated, <AuthenticatorAccount>[indexed, orphan]);
      expect(storage.values['authenticator_account_index'], isNotNull);
      expect(storage.values[indexed.id], jsonEncode(indexed.toJson()));
      expect(storage.values[orphan.id], jsonEncode(orphan.toJson()));
      expect(
        storage.values.keys.where((key) => key.startsWith('ha:v2:commit:')),
        hasLength(1),
      );

      final afterRestart = AuthenticatorLocalDataSourceImpl(
        secureStorage: storage,
        uuid: const Uuid(),
      );
      expect(await afterRestart.getAccounts(), <AuthenticatorAccount>[
        indexed,
        orphan,
      ]);
    },
  );

  test('serialize hai add đồng thời để không mất update', () async {
    storage.writeDelay = const Duration(milliseconds: 2);
    final first = _account(id: '', issuer: 'First');
    final second = _account(id: '', issuer: 'Second');

    await Future.wait(<Future<AuthenticatorAccount>>[
      dataSource.saveAccount(first),
      dataSource.saveAccount(second),
    ]);

    final accounts = await dataSource.getAccounts();
    expect(accounts.map((account) => account.issuer), <String>[
      'First',
      'Second',
    ]);
    expect(accounts.map((account) => account.id).toSet(), hasLength(2));
  });

  test('legacy index hoặc record hỏng không che các record hợp lệ', () async {
    final valid = _account(
      id: '00000000-0000-4000-8000-000000000004',
      issuer: 'Recovered',
    );
    storage.values.addAll(<String, String>{
      'authenticator_account_index': '{invalid-json',
      valid.id: jsonEncode(valid.toJson()),
      '00000000-0000-4000-8000-000000000005': '{invalid-json',
    });

    expect(await dataSource.getAccounts(), <AuthenticatorAccount>[valid]);
  });

  test('commit marker lỗi giữ snapshot hợp lệ trước đó', () async {
    final first = await dataSource.saveAccount(
      _account(id: '', issuer: 'Committed'),
    );
    storage.failNextWriteWithPrefix = 'ha:v2:commit:';

    await expectLater(
      dataSource.saveAccount(_account(id: '', issuer: 'Uncommitted')),
      throwsA(isA<StorageWriteException>()),
    );

    final afterRestart = AuthenticatorLocalDataSourceImpl(
      secureStorage: storage,
      uuid: const Uuid(),
    );
    expect(await afterRestart.getAccounts(), <AuthenticatorAccount>[first]);
  });

  test('manifest mới hỏng thì rollback về generation trước', () async {
    final first = await dataSource.saveAccount(
      _account(id: '', issuer: 'First generation'),
    );
    await dataSource.saveAccount(_account(id: '', issuer: 'Latest generation'));

    final latestCommitKey = storage.values.keys
        .where((key) => key.startsWith('ha:v2:commit:'))
        .reduce((left, right) => left.compareTo(right) > 0 ? left : right);
    final latestCommit =
        jsonDecode(storage.values[latestCommitKey]!) as Map<String, dynamic>;
    storage.values[latestCommit['manifestKey'] as String] = '{invalid-json';

    final afterRestart = AuthenticatorLocalDataSourceImpl(
      secureStorage: storage,
      uuid: const Uuid(),
    );
    expect(await afterRestart.getAccounts(), <AuthenticatorAccount>[first]);
  });

  test('delete commit không xóa legacy record được giữ để rollback', () async {
    final legacy = _account(
      id: '00000000-0000-4000-8000-000000000003',
      issuer: 'Legacy',
    );
    storage.values.addAll(<String, String>{
      'authenticator_account_index': jsonEncode(<String>[legacy.id]),
      legacy.id: jsonEncode(legacy.toJson()),
    });

    await dataSource.getAccounts();
    await dataSource.deleteAccount(legacy.id);

    expect(await dataSource.getAccounts(), isEmpty);
    expect(storage.values[legacy.id], jsonEncode(legacy.toJson()));
    expect(storage.values['authenticator_account_index'], isNotNull);
  });
}

AuthenticatorAccount _account({required String id, required String issuer}) {
  return AuthenticatorAccount(
    id: id,
    issuer: issuer,
    accountName: 'user@example.invalid',
    secretKey: 'TEST_ONLY_NOT_A_SECRET',
    algorithm: 'SHA256',
    digits: 8,
    period: 60,
  );
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};
  Duration writeDelay = Duration.zero;
  String? failNextWriteWithPrefix;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map<String, String>.from(values);
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (writeDelay > Duration.zero) {
      await Future<void>.delayed(writeDelay);
    }
    if (failNextWriteWithPrefix case final prefix?
        when key.startsWith(prefix)) {
      failNextWriteWithPrefix = null;
      throw StateError('TEST_ONLY injected storage failure');
    }
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}
