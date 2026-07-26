import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/google_authenticator_migration_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';

const _singleBatchUri =
    'otpauth-migration://offline?data='
    'CkIKElRFU1RfT05MWV9TRUNSRVRfQRIdRXhhbXBsZTphbGljZUBleGFtcGxlLmludm'
    'FsaWQaB0V4YW1wbGUgASgBMAIKPQoSVEVTVF9PTkxZX1NFQ1JFVF9CEhNib2JAZXhh'
    'bXBsZS5pbnZhbGlkGgxFeGFtcGxlIExhYnMgAigCMAIQARgBIAAokiE%3D';
const _batchPartZeroUri =
    'otpauth-migration://offline?data='
    'CkIKElRFU1RfT05MWV9TRUNSRVRfQRIdRXhhbXBsZTphbGljZUBleGFtcGxlLmludm'
    'FsaWQaB0V4YW1wbGUgASgBMAIQARgCKJMh';
const _batchPartOneUri =
    'otpauth-migration://offline?data='
    'Cj0KElRFU1RfT05MWV9TRUNSRVRfQhITYm9iQGV4YW1wbGUuaW52YWxpZBoMRXhhbX'
    'BsZSBMYWJzIAIoAjACEAEYAiABKJMh';
const _hotpUri =
    'otpauth-migration://offline?data='
    'CjQKDlRFU1RfT05MWV9IT1RQEhRob3RwQGV4YW1wbGUuaW52YWxpZBoGTGVnYWN5IA'
    'EoATABEAEYASAAKJQh';
const _defaultBatchIdUri =
    'otpauth-migration://offline?data='
    'CkIKElRFU1RfT05MWV9TRUNSRVRfQRIdRXhhbXBsZTphbGljZUBleGFtcGxlLmludm'
    'FsaWQaB0V4YW1wbGUgASgBMAIQARgC';
const _negativeBatchIdUri =
    'otpauth-migration://offline?data='
    'CkIKElRFU1RfT05MWV9TRUNSRVRfQRIdRXhhbXBsZTphbGljZUBleGFtcGxlLmludm'
    'FsaWQaB0V4YW1wbGUgASgBMAIQARgCKP%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F%2FwE%3D';

String _versionTwoUri({
  int version = 2,
  int extensionField = 8,
  bool duplicateExtension = false,
  List<int> identifier = const <int>[
    0x54,
    0x45,
    0x53,
    0x54,
    0x5f,
    0x4f,
    0x4e,
    0x4c,
    0x59,
  ],
  bool includeUnknownPayloadField = false,
}) {
  final account = <int>[];
  _writeBytesField(account, 1, utf8.encode('TEST_ONLY_SECRET_V2'));
  _writeBytesField(account, 2, utf8.encode('Example V2:alice@example.invalid'));
  _writeVarintField(account, 4, 1);
  _writeVarintField(account, 5, 1);
  _writeVarintField(account, 6, 2);
  _writeBytesField(account, extensionField, identifier);
  if (duplicateExtension) {
    _writeBytesField(account, extensionField, utf8.encode('TEST_ONLY_ID_V2_B'));
  }

  final payload = <int>[];
  _writeBytesField(payload, 1, account);
  _writeVarintField(payload, 2, version);
  _writeVarintField(payload, 3, 1);
  if (includeUnknownPayloadField) {
    _writeVarintField(payload, 6, 1);
  }
  return Uri(
    scheme: 'otpauth-migration',
    host: 'offline',
    queryParameters: {'data': base64.encode(payload)},
  ).toString();
}

void _writeBytesField(List<int> target, int field, List<int> value) {
  _writeVarint(target, (field << 3) | 2);
  _writeVarint(target, value.length);
  target.addAll(value);
}

void _writeVarintField(List<int> target, int field, int value) {
  _writeVarint(target, field << 3);
  _writeVarint(target, value);
}

void _writeVarint(List<int> target, int value) {
  var remaining = value;
  do {
    var byte = remaining & 0x7f;
    remaining >>= 7;
    if (remaining != 0) {
      byte |= 0x80;
    }
    target.add(byte);
  } while (remaining != 0);
}

void main() {
  test('parse wire shape version 2 từ Google Authenticator 7.2', () {
    final payload = GoogleAuthenticatorMigrationParser.parse(_versionTwoUri());

    expect(payload.version, 2);
    expect(payload.batchSize, 1);
    expect(payload.batchIndex, 0);
    expect(payload.batchId, 0);
    expect(payload.accounts, hasLength(1));
    expect(payload.accounts.single.issuer, 'Example V2');
    expect(payload.accounts.single.accountName, 'alice@example.invalid');
    expect(payload.accounts.single.algorithm, 'SHA1');
    expect(payload.accounts.single.digits, 6);
    expect(payload.accounts.single.period, 30);
  });

  test('version 2 chỉ nhận extension identifier đã quan sát', () {
    expect(
      () => GoogleAuthenticatorMigrationParser.parse(
        _versionTwoUri(extensionField: 9),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('metadata tài khoản'),
        ),
      ),
    );
    expect(
      () => GoogleAuthenticatorMigrationParser.parse(
        _versionTwoUri(duplicateExtension: true),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => GoogleAuthenticatorMigrationParser.parse(
        _versionTwoUri(identifier: const <int>[]),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => GoogleAuthenticatorMigrationParser.parse(
        _versionTwoUri(identifier: List<int>.filled(257, 0x41)),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('version 2 chặn top-level metadata chưa quan sát', () {
    expect(
      () => GoogleAuthenticatorMigrationParser.parse(
        _versionTwoUri(includeUnknownPayloadField: true),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('metadata chưa được hỗ trợ'),
        ),
      ),
    );
  });

  test('version chưa được quan sát tiếp tục fail closed', () {
    expect(
      () =>
          GoogleAuthenticatorMigrationParser.parse(_versionTwoUri(version: 3)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Version export'),
        ),
      ),
    );
  });

  test('parse fixture version 1 giữ issuer/name/algorithm/digits', () {
    final payload = GoogleAuthenticatorMigrationParser.parse(_singleBatchUri);

    expect(payload.version, 1);
    expect(payload.batchSize, 1);
    expect(payload.batchIndex, 0);
    expect(payload.accounts, hasLength(2));
    expect(payload.accounts.first.issuer, 'Example');
    expect(payload.accounts.first.accountName, 'alice@example.invalid');
    expect(
      payload.accounts.first.secretKey,
      'KRCVGVC7'
      'J5HEYWK7'
      'KNCUGUSF'
      'KRPUC',
    );
    expect(payload.accounts.first.algorithm, 'SHA1');
    expect(payload.accounts.first.digits, 6);
    expect(payload.accounts.first.period, 30);
    expect(payload.accounts.last.issuer, 'Example Labs');
    expect(payload.accounts.last.accountName, 'bob@example.invalid');
    expect(
      payload.accounts.last.secretKey,
      'KRCVGVC7'
      'J5HEYWK7'
      'KNCUGUSF'
      'KRPUE',
    );
    expect(payload.accounts.last.algorithm, 'SHA256');
    expect(payload.accounts.last.digits, 8);
    expect(payload.toString(), isNot(contains('KRCVGVC7')));
    expect(payload.accounts.first.toString(), contains('[REDACTED]'));
  });

  test('collector nhận multi-part out-of-order và chỉ complete khi đủ', () {
    final collector = GoogleAuthenticatorMigrationBatchCollector();
    final second = GoogleAuthenticatorMigrationParser.parse(_batchPartOneUri);
    final first = GoogleAuthenticatorMigrationParser.parse(_batchPartZeroUri);

    final pending = collector.add(second);
    expect(pending.isComplete, isFalse);
    expect(pending.scannedParts, 1);
    expect(pending.totalParts, 2);
    expect(collector.hasPendingBatch, isTrue);

    final complete = collector.add(first);
    expect(complete.isComplete, isTrue);
    expect(complete.accounts!.map((account) => account.accountName), [
      'alice@example.invalid',
      'bob@example.invalid',
    ]);
    expect(collector.hasPendingBatch, isFalse);
  });

  test('proto3 default field và signed batch_id giữ interoperability', () {
    final defaultBatch = GoogleAuthenticatorMigrationParser.parse(
      _defaultBatchIdUri,
    );
    final negativeBatch = GoogleAuthenticatorMigrationParser.parse(
      _negativeBatchIdUri,
    );

    expect(defaultBatch.batchIndex, 0);
    expect(defaultBatch.batchId, 0);
    expect(negativeBatch.batchIndex, 0);
    expect(negativeBatch.batchId, -1);
  });

  test('scan lặp cùng part không tăng progress', () {
    final collector = GoogleAuthenticatorMigrationBatchCollector();
    final first = GoogleAuthenticatorMigrationParser.parse(_batchPartZeroUri);

    expect(collector.add(first).scannedParts, 1);
    expect(collector.add(first).scannedParts, 1);
  });

  test('collector chặn tổng account vượt giới hạn dù chia nhiều part', () {
    final source = GoogleAuthenticatorMigrationParser.parse(
      _singleBatchUri,
    ).accounts.first;
    final collector = GoogleAuthenticatorMigrationBatchCollector();
    collector.add(
      GoogleAuthenticatorMigrationPayload(
        accounts: List<ParsedTotpAccount>.filled(100, source),
        version: 1,
        batchSize: 2,
        batchIndex: 0,
        batchId: 999,
      ),
    );

    expect(
      () => collector.add(
        GoogleAuthenticatorMigrationPayload(
          accounts: [source],
          version: 1,
          batchSize: 2,
          batchIndex: 1,
          batchId: 999,
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('quá nhiều tài khoản'),
        ),
      ),
    );
  });

  test('collector từ chối QR thuộc batch khác nhưng giữ batch đang quét', () {
    final collector = GoogleAuthenticatorMigrationBatchCollector();
    final first = GoogleAuthenticatorMigrationParser.parse(_batchPartZeroUri);
    collector.add(first);

    expect(
      () => collector.add(
        GoogleAuthenticatorMigrationParser.parse(_singleBatchUri),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('đợt export'),
        ),
      ),
    );
    expect(collector.scannedParts, 1);
    expect(
      collector
          .add(GoogleAuthenticatorMigrationParser.parse(_batchPartOneUri))
          .isComplete,
      isTrue,
    );
  });

  test('HOTP fail closed và không trả partial account', () {
    expect(
      () => GoogleAuthenticatorMigrationParser.parse(_hotpUri),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('HOTP chưa được hỗ trợ'),
        ),
      ),
    );
  });

  test('URI hoặc Base64 sai bị từ chối bằng lỗi không chứa payload', () {
    expect(
      () =>
          GoogleAuthenticatorMigrationParser.parse('otpauth://totp/TEST_ONLY'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => GoogleAuthenticatorMigrationParser.parse(
        'otpauth-migration://offline?data=%25%25%25',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          isNot(contains('%%%')),
        ),
      ),
    );
  });
}
