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

void main() {
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
      'KRCVGVC7' 'J5HEYWK7' 'KNCUGUSF' 'KRPUC',
    );
    expect(payload.accounts.first.algorithm, 'SHA1');
    expect(payload.accounts.first.digits, 6);
    expect(payload.accounts.first.period, 30);
    expect(payload.accounts.last.issuer, 'Example Labs');
    expect(payload.accounts.last.accountName, 'bob@example.invalid');
    expect(
      payload.accounts.last.secretKey,
      'KRCVGVC7' 'J5HEYWK7' 'KNCUGUSF' 'KRPUE',
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
