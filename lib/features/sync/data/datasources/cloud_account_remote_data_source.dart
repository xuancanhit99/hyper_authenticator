import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/account_payload_validator.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/cloud_account_record.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/cloud_account_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@LazySingleton(as: CloudAccountRepository)
class CloudAccountRemoteDataSource implements CloudAccountRepository {
  static const listFunctionName = 'list_authenticator_accounts';
  static const upsertFunctionName = 'upsert_authenticator_account';
  static const deleteFunctionName = 'delete_authenticator_account';
  static final _accountIdPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  CloudAccountRemoteDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CloudAccountRecord>> list({required String userId}) async {
    final token = _requireAuthenticatedUser(userId);
    try {
      final response = await _client
          .rpc(listFunctionName)
          .setHeader('Authorization', 'Bearer $token');
      if (response is! List) {
        throw const FormatException('Cloud list response không hợp lệ.');
      }
      return response
          .map((row) {
            if (row is! Map) {
              throw const FormatException('Cloud account row không hợp lệ.');
            }
            return _parseRecord(
              Map<String, dynamic>.from(row),
              quarantineInvalidPayload: true,
            );
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
    final token = _requireAuthenticatedUser(userId);
    try {
      final response = await _client
          .rpc(
            upsertFunctionName,
            params: {
              'p_account_id': account.id,
              'p_expected_revision': expectedRevision,
              'p_payload': _payload(account),
            },
          )
          .setHeader('Authorization', 'Bearer $token');
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
    final token = _requireAuthenticatedUser(userId);
    try {
      final response = await _client
          .rpc(
            deleteFunctionName,
            params: {
              'p_account_id': accountId,
              'p_expected_revision': expectedRevision,
            },
          )
          .setHeader('Authorization', 'Bearer $token');
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

  CloudAccountRecord _parseRecord(
    Map<String, dynamic> row, {
    bool quarantineInvalidPayload = false,
  }) {
    final accountId = row['account_id'];
    final revision = row['revision'];
    final updatedAt = row['updated_at'];
    final deletedAt = row['deleted_at'];
    final payload = row['payload'];
    if (accountId is! String ||
        !_accountIdPattern.hasMatch(accountId) ||
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
    var isBlocked = false;
    if (parsedDeletedAt == null) {
      try {
        account = _parseAccountPayload(accountId, payload);
      } on FormatException {
        if (!quarantineInvalidPayload) rethrow;
        // Keep only trusted identity/revision metadata. Never treat an invalid
        // live row as a tombstone or carry its credential into synchronization.
        isBlocked = true;
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
      isBlocked: isBlocked,
    );
  }

  AuthenticatorAccount _parseAccountPayload(String accountId, Object? payload) {
    if (payload is! Map || payload.keys.any((key) => key is! String)) {
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
    final account = AuthenticatorAccount(
      id: accountId,
      issuer: issuer,
      accountName: accountName,
      secretKey: secretKey,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
    AccountPayloadValidator.validateCloudAccount(account);
    return account;
  }

  Map<String, Object> _payload(AuthenticatorAccount account) => {
    'issuer': account.issuer,
    'accountName': account.accountName,
    'secretKey': account.secretKey,
    'algorithm': account.algorithm,
    'digits': account.digits,
    'period': account.period,
  };

  String _requireAuthenticatedUser(String expectedUserId) {
    final session = _client.auth.currentSession;
    if (session == null || session.user.id != expectedUserId) {
      throw const AuthException('Authenticated user changed during sync');
    }
    return session.accessToken;
  }
}
