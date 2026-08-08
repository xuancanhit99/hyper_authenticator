import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_validator.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/cloud_account_record.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/cloud_account_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@LazySingleton(as: CloudAccountRepository)
class CloudAccountRemoteDataSource implements CloudAccountRepository {
  static const listFunctionName = 'list_authenticator_accounts';
  static const upsertFunctionName = 'upsert_authenticator_account';
  static const deleteFunctionName = 'delete_authenticator_account';

  CloudAccountRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CloudAccountRecord>> list({required String userId}) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(listFunctionName);
      if (response is! List) {
        throw const FormatException('Cloud list response không hợp lệ.');
      }
      return response
          .map((row) {
            if (row is! Map) {
              throw const FormatException('Cloud account row không hợp lệ.');
            }
            return _parseRecord(Map<String, dynamic>.from(row));
          })
          .toList(growable: false);
    } on PostgrestException {
      throw const ServerException('Không thể tải mã từ cloud.');
    } on FormatException {
      throw const ServerException('Dữ liệu cloud có format không hợp lệ.');
    }
  }

  @override
  Future<CloudAccountRecord> upsert({
    required String userId,
    required AuthenticatorAccount account,
    required int expectedRevision,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        upsertFunctionName,
        params: {
          'p_account_id': account.id,
          'p_expected_revision': expectedRevision,
          'p_payload': _payload(account),
        },
      );
      return _singleRecord(response);
    } on PostgrestException catch (error) {
      if (error.code == 'PT409' ||
          error.message.contains('revision_conflict')) {
        throw const CloudAccountRevisionConflictException();
      }
      if (error.code == 'PT410' || error.message.contains('account_deleted')) {
        throw const CloudAccountTombstonedException();
      }
      throw const ServerException('Không thể upload mã lên cloud.');
    } on FormatException {
      throw const ServerException('Cloud upsert response không hợp lệ.');
    }
  }

  @override
  Future<CloudAccountRecord> delete({
    required String userId,
    required String accountId,
    required int expectedRevision,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        deleteFunctionName,
        params: {
          'p_account_id': accountId,
          'p_expected_revision': expectedRevision,
        },
      );
      return _singleRecord(response);
    } on PostgrestException catch (error) {
      if (error.code == 'PT409' ||
          error.message.contains('revision_conflict')) {
        throw const CloudAccountRevisionConflictException();
      }
      throw const ServerException('Không thể xóa mã trên cloud.');
    } on FormatException {
      throw const ServerException('Cloud delete response không hợp lệ.');
    }
  }

  CloudAccountRecord _singleRecord(Object? response) {
    if (response is! List || response.length != 1 || response.single is! Map) {
      throw const FormatException('Cloud mutation response không hợp lệ.');
    }
    return _parseRecord(Map<String, dynamic>.from(response.single as Map));
  }

  CloudAccountRecord _parseRecord(Map<String, dynamic> row) {
    final accountId = row['account_id'];
    final revision = row['revision'];
    final updatedAt = row['updated_at'];
    final deletedAt = row['deleted_at'];
    final payload = row['payload'];
    if (accountId is! String ||
        accountId.isEmpty ||
        revision is! int ||
        revision <= 0 ||
        updatedAt is! String ||
        (deletedAt != null && deletedAt is! String)) {
      throw const FormatException('Cloud account metadata không hợp lệ.');
    }
    final parsedUpdatedAt = DateTime.tryParse(updatedAt)?.toUtc();
    final parsedDeletedAt = deletedAt == null
        ? null
        : DateTime.tryParse(deletedAt as String)?.toUtc();
    if (parsedUpdatedAt == null ||
        (deletedAt != null && parsedDeletedAt == null)) {
      throw const FormatException('Cloud account timestamp không hợp lệ.');
    }

    AuthenticatorAccount? account;
    if (parsedDeletedAt == null) {
      if (payload is! Map) {
        throw const FormatException('Cloud account payload bị thiếu.');
      }
      final decoded = Map<String, dynamic>.from(payload);
      final issuer = decoded['issuer'];
      final accountName = decoded['accountName'];
      final secretKey = decoded['secretKey'];
      final algorithm = decoded['algorithm'];
      final digits = decoded['digits'];
      final period = decoded['period'];
      if (decoded.length != 6 ||
          issuer is! String ||
          accountName is! String ||
          secretKey is! String ||
          algorithm is! String ||
          digits is! int ||
          period is! int) {
        throw const FormatException('Cloud account payload không hợp lệ.');
      }
      account = AuthenticatorAccount(
        id: accountId,
        issuer: issuer,
        accountName: accountName,
        secretKey: secretKey,
        algorithm: algorithm,
        digits: digits,
        period: period,
      );
      final normalizedSecret = TotpValidator.normalizeSecret(account.secretKey);
      final normalizedAlgorithm = TotpValidator.normalizeAlgorithm(
        account.algorithm,
      );
      TotpValidator.validateParameters(
        digits: account.digits,
        period: account.period,
      );
      if (account.accountName.isEmpty ||
          normalizedSecret != account.secretKey ||
          normalizedAlgorithm != account.algorithm ||
          account.secretKey.length < 16 ||
          account.secretKey.length > 1024 ||
          account.issuer.length > 256 ||
          account.accountName.length > 512) {
        throw const FormatException('Cloud account payload không hợp lệ.');
      }
    } else if (payload != null) {
      throw const FormatException('Tombstone không được chứa payload.');
    }

    return CloudAccountRecord(
      accountId: accountId,
      revision: revision,
      updatedAt: parsedUpdatedAt,
      deletedAt: parsedDeletedAt,
      account: account,
    );
  }

  Map<String, Object> _payload(AuthenticatorAccount account) => {
    'issuer': account.issuer,
    'accountName': account.accountName,
    'secretKey': account.secretKey,
    'algorithm': account.algorithm,
    'digits': account.digits,
    'period': account.period,
  };

  void _requireAuthenticatedUser(String expectedUserId) {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null || currentUser.id != expectedUserId) {
      throw const AuthException('Authenticated user changed during sync');
    }
  }
}
