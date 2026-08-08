import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_signal.dart';

/// Private Realtime chỉ phát wake-up signal; account data luôn đi qua sync RPC.
abstract class AccountSyncSignalRepository {
  Stream<AccountSyncSignal> watch({required String userId});
}
