import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase/supabase.dart';

const _event = 'account-sync-changed';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/agent/test_account_sync_realtime.dart CONFIG_JSON',
    );
    exitCode = 64;
    return;
  }

  SupabaseClient? clientA;
  SupabaseClient? clientB;
  var stage = 'bootstrap';
  try {
    final file = File(arguments.single);
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) throw const FormatException();

    final baseUrl = _requiredString(decoded, 'baseUrl');
    final publishableKey = _requiredString(decoded, 'publishableKey');
    final userAId = _requiredString(decoded, 'userAId');
    final accessTokenA = _requiredString(decoded, 'accessTokenA');
    final accessTokenB = _requiredString(decoded, 'accessTokenB');
    final accountId = _requiredString(decoded, 'accountId');
    final testSecret = _requiredString(decoded, 'testSecret');
    final topic = 'account-sync:$userAId';

    clientA = SupabaseClient(
      baseUrl,
      publishableKey,
      accessToken: () async => accessTokenA,
    );
    clientB = SupabaseClient(
      baseUrl,
      publishableKey,
      accessToken: () async => accessTokenB,
    );
    await clientA.realtime.setAuth(accessTokenA);
    await clientB.realtime.setAuth(accessTokenB);

    final received = Completer<Map<String, dynamic>>();
    final channelA =
        clientA.channel(
          topic,
          opts: const RealtimeChannelConfig(
            private: true,
            ack: true,
            self: false,
          ),
        )..onBroadcast(
          event: _event,
          callback: (payload) {
            if (!received.isCompleted) received.complete(payload);
          },
        );
    final channelB = clientB.channel(
      topic,
      opts: const RealtimeChannelConfig(private: true, ack: true, self: false),
    );

    stage = 'owner-subscribe';
    final subscriptionA = await _subscribe(channelA);
    if (subscriptionA.status != RealtimeSubscribeStatus.subscribed) {
      throw _ContractFailure(
        'Owner không join được private topic '
        '(${subscriptionA.status.name}/${subscriptionA.errorCategory}).',
      );
    }
    stage = 'cross-user-subscribe';
    final subscriptionB = await _subscribe(channelB);
    if (subscriptionB.status == RealtimeSubscribeStatus.subscribed) {
      throw const _ContractFailure('User khác đã join được private topic.');
    }

    stage = 'client-send-denial';
    final clientSend = await channelA.sendBroadcastMessage(
      event: _event,
      payload: {'version': 1},
    );
    if (clientSend == ChannelResponse.ok) {
      throw const _ContractFailure('Client đã tự phát được sync signal.');
    }

    stage = 'database-upsert';
    final response = await clientA.rpc<List<dynamic>>(
      'upsert_authenticator_account',
      params: {
        'p_account_id': accountId,
        'p_expected_revision': 0,
        'p_payload': {
          'issuer': 'TEST ONLY realtime contract',
          'accountName': 'realtime-contract@example.invalid',
          'secretKey': testSecret,
          'algorithm': 'SHA1',
          'digits': 6,
          'period': 30,
        },
      },
    );
    if (response.length != 1 || response.single is! Map) {
      throw const _ContractFailure('Realtime fixture upsert sai response.');
    }
    final revision = (response.single as Map)['revision'];
    if (revision is! int || revision != 1) {
      throw const _ContractFailure('Realtime fixture sai revision.');
    }

    stage = 'signal-receive';
    final message = await received.future.timeout(const Duration(seconds: 20));
    _verifyCredentialFreeMessage(message, testSecret);

    stage = 'database-delete';
    await clientA.rpc<List<dynamic>>(
      'delete_authenticator_account',
      params: {'p_account_id': accountId, 'p_expected_revision': revision},
    );

    stdout.writeln(
      'Realtime remote contract pass: own-topic receive, cross-user deny, client-send deny và credential-free signal.',
    );
  } on TimeoutException {
    stderr.writeln(
      'Realtime remote contract timeout; không nhận được signal hợp lệ.',
    );
    exitCode = 1;
  } catch (error) {
    stderr.writeln(
      error is _ContractFailure
          ? error.message
          : 'Realtime remote contract thất bại an toàn '
                '($stage/${error.runtimeType}).',
    );
    exitCode = 1;
  } finally {
    await clientA?.dispose();
    await clientB?.dispose();
  }
}

Future<_SubscriptionResult> _subscribe(RealtimeChannel channel) {
  final completer = Completer<_SubscriptionResult>();
  channel.subscribe((status, error) {
    if (!completer.isCompleted &&
        (status == RealtimeSubscribeStatus.subscribed ||
            status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed)) {
      completer.complete(
        _SubscriptionResult(status, _classifySubscriptionError(error)),
      );
    }
  });
  return completer.future.timeout(const Duration(seconds: 20));
}

String _classifySubscriptionError(Object? error) {
  if (error == null) return 'none';
  final message = error.toString().toLowerCase();
  if (message.contains('permission') || message.contains('unauthorized')) {
    return 'authorization-denied';
  }
  if (message.contains('jwt') || message.contains('token')) {
    return 'token-rejected';
  }
  if (message.contains('timeout')) return 'timeout';
  if (message.contains('socket') || message.contains('connection')) {
    return 'connection-error';
  }
  return error.runtimeType.toString();
}

void _verifyCredentialFreeMessage(
  Map<String, dynamic> message,
  String testSecret,
) {
  final encoded = jsonEncode(message);
  const forbiddenNames = [
    'issuer',
    'accountName',
    'secretKey',
    'vault_secret_id',
    'account_id',
    'revision',
  ];
  if (encoded.contains(testSecret) || forbiddenNames.any(encoded.contains)) {
    throw const _ContractFailure(
      'Realtime signal chứa account credential/metadata.',
    );
  }

  final payload = message['payload'] is Map
      ? Map<String, dynamic>.from(message['payload'] as Map)
      : message;
  if (payload['version'] != 1 ||
      !payload.containsKey('id') ||
      payload.keys.any((key) => key != 'version' && key != 'id')) {
    throw const _ContractFailure('Realtime signal vượt payload allowlist.');
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw const FormatException();
  return value;
}

class _ContractFailure implements Exception {
  const _ContractFailure(this.message);

  final String message;
}

class _SubscriptionResult {
  const _SubscriptionResult(this.status, this.errorCategory);

  final RealtimeSubscribeStatus status;
  final String errorCategory;
}
