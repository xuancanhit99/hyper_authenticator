import 'dart:async';

import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_signal.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_signal_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@LazySingleton(as: AccountSyncSignalRepository)
class SupabaseAccountSyncSignalRepository
    implements AccountSyncSignalRepository {
  SupabaseAccountSyncSignalRepository(this._client);

  static const changeEvent = 'account-sync-changed';
  static const _topicPrefix = 'account-sync:';

  final SupabaseClient _client;

  @override
  Stream<AccountSyncSignal> watch({required String userId}) {
    var cancelled = false;
    RealtimeChannel? channel;
    late final StreamController<AccountSyncSignal> controller;

    Future<void> start() async {
      try {
        final session = _client.auth.currentSession;
        if (session == null || session.user.id != userId) {
          throw const _AccountSyncSignalUnavailable();
        }
        await _client.realtime.setAuth(session.accessToken);
        if (cancelled || _client.auth.currentUser?.id != userId) return;

        final activeChannel = _client.channel(
          topicForUser(userId),
          opts: const RealtimeChannelConfig(private: true, self: false),
        );
        channel = activeChannel;
        activeChannel
            .onBroadcast(
              event: changeEvent,
              callback: (_) {
                if (!cancelled && !controller.isClosed) {
                  controller.add(AccountSyncSignal.changed);
                }
              },
            )
            .subscribe((status, _) {
              if (status == RealtimeSubscribeStatus.subscribed &&
                  !cancelled &&
                  !controller.isClosed) {
                // Mỗi reconnect đều chạy full sync để bù signal có thể đã mất.
                controller.add(AccountSyncSignal.connected);
              }
            });
      } catch (_) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(const _AccountSyncSignalUnavailable());
        }
      }
    }

    controller = StreamController<AccountSyncSignal>(
      onListen: () => unawaited(start()),
      onCancel: () {
        cancelled = true;
        final activeChannel = channel;
        if (activeChannel != null) {
          unawaited(_client.removeChannel(activeChannel));
        }
      },
    );
    return controller.stream;
  }

  static String topicForUser(String userId) => '$_topicPrefix$userId';
}

class _AccountSyncSignalUnavailable implements Exception {
  const _AccountSyncSignalUnavailable();

  @override
  String toString() => 'AccountSyncSignalUnavailable([REDACTED])';
}
