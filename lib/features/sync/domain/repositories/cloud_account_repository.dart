import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/cloud_account_record.dart';

class CloudAccountRevisionConflictException implements Exception {
  const CloudAccountRevisionConflictException();
}

class CloudAccountTombstonedException implements Exception {
  const CloudAccountTombstonedException();
}

abstract class CloudAccountRepository {
  Future<List<CloudAccountRecord>> list({required String userId});

  Future<CloudAccountRecord> upsert({
    required String userId,
    required AuthenticatorAccount account,
    required int expectedRevision,
  });

  Future<CloudAccountRecord> delete({
    required String userId,
    required String accountId,
    required int expectedRevision,
  });
}
