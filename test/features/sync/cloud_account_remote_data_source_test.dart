import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/cloud_account_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/cloud_account_record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '00000000-0000-4000-8000-000000000001';
const _firstId = '00000000-0000-4000-8000-000000000002';
const _secondId = '00000000-0000-4000-8000-000000000003';
const _timestamp = '2026-10-19T00:00:00Z';

void main() {
  late _RpcHarness harness;

  setUp(() async => harness = await _RpcHarness.create());
  tearDown(() async => harness.dispose());

  test('list cô lập live payload Base32 lỗi và giữ record hợp lệ', () async {
    harness.rows = [
      _row(_firstId, payload: _payload(secret: 'A' * 17)),
      _row(_secondId),
    ];

    final records = await harness.source.list(userId: _userId);

    expect(records, hasLength(2));
    expect(records.first.accountId, _firstId);
    expect(records.first.revision, 2);
    expect(records.first.updatedAt, DateTime.parse(_timestamp));
    expect(records.first.account, isNull);
    expect(records.first.isBlocked, isTrue);
    expect(records.first.isDeleted, isFalse);
    expect(records.last.account?.id, _secondId);
    expect(records.last.isBlocked, isFalse);
    expect(harness.paths, ['/rest/v1/rpc/list_authenticator_accounts']);
  });

  test(
    'list cô lập bounds/types thiếu hoặc sai nhưng không giữ credential',
    () async {
      final malformed = <Object?>[
        null,
        [],
        _payload()..remove('secretKey'),
        _payload()..['issuer'] = 'I' * 257,
        _payload()..['accountName'] = 12,
        _payload(secret: 'A' * 1032),
        _payload()..['algorithm'] = 'MD5',
        _payload()..['digits'] = 6.5,
        _payload()..['period'] = 0,
      ];
      for (final payload in malformed) {
        harness.rows = [_row(_firstId, payload: payload), _row(_secondId)];
        final records = await harness.source.list(userId: _userId);
        expect(records, hasLength(2));
        expect(records.first.account, isNull);
        expect(records.first.isBlocked, isTrue);
        expect(records.first.isDeleted, isFalse);
        expect(records.last.account, isNotNull);
        expect(records.first.toString(), isNot(contains(_firstId)));
        expect(records.first.toString(), isNot(contains('secretKey')));
      }
    },
  );

  test('metadata lỗi dừng list thay vì trở thành blocked record', () async {
    for (final patch in <Map<String, Object?>>[
      {'account_id': ''},
      {'account_id': 'not-a-uuid'},
      {'revision': 0},
      {'revision': 1.5},
      {'updated_at': 'not-a-date'},
      {'deleted_at': 12},
      {'deleted_at': 'not-a-date'},
    ]) {
      harness.rows = [
        {..._row(_firstId), ...patch},
        _row(_secondId),
      ];
      await expectLater(
        harness.source.list(userId: _userId),
        throwsA(isA<ServerException>()),
      );
    }
  });

  test(
    'tombstone chỉ nhận payload null, không quarantine delete intent',
    () async {
      harness.rows = [
        {..._row(_firstId), 'deleted_at': _timestamp},
      ];
      await expectLater(
        harness.source.list(userId: _userId),
        throwsA(isA<ServerException>()),
      );

      harness.rows = [
        {..._row(_firstId, payload: null), 'deleted_at': _timestamp},
      ];
      final records = await harness.source.list(userId: _userId);
      expect(records.single.isDeleted, isTrue);
      expect(records.single.isBlocked, isFalse);
      expect(records.single.account, isNull);
    },
  );

  test('mutation response payload lỗi vẫn fail closed', () async {
    harness.rows = [_row(_firstId, payload: _payload(secret: 'A' * 17))];
    const account = AuthenticatorAccount(
      id: _firstId,
      issuer: 'TEST_ONLY',
      accountName: 'demo@example.invalid',
      secretKey: 'JBSWY3DPEHPK3PXP',
    );
    await expectLater(
      harness.source.upsert(
        userId: _userId,
        account: account,
        expectedRevision: 1,
      ),
      throwsA(isA<ServerException>()),
    );
    await expectLater(
      harness.source.delete(
        userId: _userId,
        accountId: _firstId,
        expectedRevision: 1,
      ),
      throwsA(isA<ServerException>()),
    );
  });

  test('payload legacy padded hợp lệ vẫn giữ nguyên khi đọc cloud', () async {
    const padded = 'MZXW6YTBOI======';
    harness.rows = [_row(_firstId, payload: _payload(secret: padded))];
    final records = await harness.source.list(userId: _userId);
    expect(records.single.account?.secretKey, padded);
  });

  test('sai user bị chặn trước RPC', () async {
    await expectLater(
      harness.source.list(userId: _secondId),
      throwsA(isA<AuthException>()),
    );
    expect(harness.paths, isEmpty);
  });

  test('blocked status thuộc equality và toString không lộ metadata', () {
    final updatedAt = DateTime.parse(_timestamp);
    final blocked = CloudAccountRecord(
      accountId: _firstId,
      revision: 2,
      updatedAt: updatedAt,
      deletedAt: null,
      account: null,
      isBlocked: true,
    );
    final unblocked = CloudAccountRecord(
      accountId: _firstId,
      revision: 2,
      updatedAt: updatedAt,
      deletedAt: null,
      account: null,
    );
    expect(blocked, isNot(unblocked));
    expect(blocked.toString(), contains('isBlocked: true'));
    expect(blocked.toString(), isNot(contains(_firstId)));
    expect(blocked.toString(), isNot(contains(_timestamp)));
  });
}

Map<String, Object?> _payload({String secret = 'JBSWY3DPEHPK3PXP'}) => {
  'issuer': 'TEST_ONLY',
  'accountName': 'demo@example.invalid',
  'secretKey': secret,
  'algorithm': 'SHA1',
  'digits': 6,
  'period': 30,
};

const _defaultPayload = Object();

Map<String, Object?> _row(String id, {Object? payload = _defaultPayload}) => {
  'account_id': id,
  'revision': 2,
  'updated_at': _timestamp,
  'deleted_at': null,
  'payload': identical(payload, _defaultPayload) ? _payload() : payload,
};

class _RpcHarness {
  _RpcHarness(this.server, this.client);

  final HttpServer server;
  final SupabaseClient client;
  List<Map<String, Object?>> rows = [];
  final paths = <String>[];
  CloudAccountRemoteDataSource get source =>
      CloudAccountRemoteDataSource(client);

  static Future<_RpcHarness> create() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://${server.address.address}:${server.port}',
      'TEST_ONLY_PUBLIC_KEY',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final harness = _RpcHarness(server, client);
    server.listen((request) async {
      harness.paths.add(request.uri.path);
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(harness.rows));
      await request.response.close();
    });
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final jwt =
        '${encode({'alg': 'HS256', 'typ': 'JWT'})}.${encode({'sub': _userId, 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.TEST_ONLY';
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': jwt,
        'refresh_token': 'TEST_ONLY',
        'token_type': 'bearer',
        'user': {
          'id': _userId,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': _timestamp,
        },
      }),
    );
    return harness;
  }

  Future<void> dispose() async {
    await client.dispose();
    await server.close(force: true);
  }
}
