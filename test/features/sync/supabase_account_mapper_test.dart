import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/data/mappers/supabase_account_mapper.dart';

void main() {
  const account = AuthenticatorAccount(
    id: '00000000-0000-4000-8000-000000000001',
    issuer: 'Example',
    accountName: 'user@example.invalid',
    secretKey: 'TEST_ONLY_NOT_A_SECRET',
    algorithm: 'SHA256',
    digits: 8,
    period: 60,
  );

  test('toRow dùng snake_case và giữ toàn bộ tham số TOTP', () {
    final row = SupabaseAccountMapper.toRow(
      account,
      userId: '00000000-0000-4000-8000-000000000002',
    );

    expect(row, <String, dynamic>{
      'user_id': '00000000-0000-4000-8000-000000000002',
      'account_id': '00000000-0000-4000-8000-000000000001',
      'issuer': 'Example',
      'account_name': 'user@example.invalid',
      'secret_key': 'TEST_ONLY_NOT_A_SECRET',
      'algorithm': 'SHA256',
      'digits': 8,
      'period': 60,
    });
    expect(row, isNot(contains('accountName')));
    expect(row, isNot(contains('secretKey')));
  });

  test('fromRow round-trip đầy đủ từ PostgreSQL contract', () {
    final restored = SupabaseAccountMapper.fromRow(<String, dynamic>{
      'user_id': '00000000-0000-4000-8000-000000000002',
      'account_id': '00000000-0000-4000-8000-000000000001',
      'issuer': 'Example',
      'account_name': 'user@example.invalid',
      'secret_key': 'TEST_ONLY_NOT_A_SECRET',
      'algorithm': 'SHA256',
      'digits': 8,
      'period': 60,
      'format_version': 1,
      'updated_at': '2026-07-17T00:00:00Z',
    });

    expect(restored, account);
  });
}
