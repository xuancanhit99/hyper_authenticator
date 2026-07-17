import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';

/// Chuyển đổi giữa model local (camelCase) và row PostgreSQL (snake_case).
///
/// Mapper không log payload vì [secretKey] là credential.
class SupabaseAccountMapper {
  const SupabaseAccountMapper._();

  static AuthenticatorAccount fromRow(Map<String, dynamic> row) {
    return AuthenticatorAccount(
      id: row['account_id'] as String,
      issuer: row['issuer'] as String,
      accountName: row['account_name'] as String,
      secretKey: row['secret_key'] as String,
      algorithm: row['algorithm'] as String,
      digits: row['digits'] as int,
      period: row['period'] as int,
    );
  }

  static Map<String, dynamic> toRow(
    AuthenticatorAccount account, {
    required String userId,
  }) {
    return <String, dynamic>{
      'user_id': userId,
      'account_id': account.id,
      'issuer': account.issuer,
      'account_name': account.accountName,
      'secret_key': account.secretKey,
      'algorithm': account.algorithm,
      'digits': account.digits,
      'period': account.period,
    };
  }
}
