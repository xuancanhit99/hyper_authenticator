import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';
import 'package:hyper_authenticator/features/settings/domain/repositories/authenticator_device_session_repository.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/device_session_bloc.dart';

void main() {
  final current = AuthenticatorDeviceSession(
    registrationId: '10000000-0000-4000-8000-000000000001',
    displayName: 'Hyper Authenticator trên macOS',
    platform: 'macos',
    registeredAt: DateTime.utc(2026, 7, 19, 1),
    lastSeenAt: DateTime.utc(2026, 7, 19, 2),
    isCurrent: true,
  );
  final other = AuthenticatorDeviceSession(
    registrationId: '10000000-0000-4000-8000-000000000002',
    displayName: 'Hyper Authenticator trên Windows',
    platform: 'windows',
    registeredAt: DateTime.utc(2026, 7, 18, 1),
    lastSeenAt: DateTime.utc(2026, 7, 18, 2),
    isCurrent: false,
  );

  late _FakeDeviceSessionRepository repository;
  late DeviceSessionBloc bloc;

  setUp(() {
    repository = _FakeDeviceSessionRepository([current, other]);
    bloc = DeviceSessionBloc(repository);
  });

  tearDown(() => bloc.close());

  test('load bind user và trả danh sách có current session', () async {
    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<DeviceSessionLoading>(),
        isA<DeviceSessionsLoaded>().having(
          (state) => state.devices,
          'devices',
          [current, other],
        ),
      ]),
    );

    bloc.add(const LoadDeviceSessionsRequested('test-user'));

    await states;
    expect(repository.loadCalls, 1);
    expect(repository.lastUserId, 'test-user');
  });

  test('double load khi pending chỉ tạo một remote operation', () async {
    final pending =
        Completer<Either<Failure, List<AuthenticatorDeviceSession>>>();
    repository.pendingLoad = pending;
    final loading = bloc.stream.firstWhere(
      (state) => state is DeviceSessionLoading,
    );

    bloc
      ..add(const LoadDeviceSessionsRequested('test-user'))
      ..add(const LoadDeviceSessionsRequested('test-user'));

    await loading;
    await Future<void>.delayed(Duration.zero);
    expect(repository.loadCalls, 1);
    pending.complete(Right([current, other]));
    await bloc.stream.firstWhere((state) => state is DeviceSessionsLoaded);
  });

  test(
    'account đổi khi load pending không emit device state của user cũ',
    () async {
      final pending =
          Completer<Either<Failure, List<AuthenticatorDeviceSession>>>();
      repository.pendingLoad = pending;
      final states = <DeviceSessionState>[];
      final subscription = bloc.stream.listen(states.add);
      addTearDown(subscription.cancel);

      bloc.add(const LoadDeviceSessionsRequested('user-a'));
      await bloc.stream.firstWhere((state) => state is DeviceSessionLoading);
      bloc.add(const LoadDeviceSessionsRequested('user-b'));
      await Future<void>.delayed(Duration.zero);

      pending.complete(Right([current, other]));
      final loadedForB = await bloc.stream.firstWhere(
        (state) => state is DeviceSessionsLoaded && state.userId == 'user-b',
      );

      expect(loadedForB.devices, [current, other]);
      expect(
        states.whereType<DeviceSessionsLoaded>().map((state) => state.userId),
        isNot(contains('user-a')),
      );
      expect(repository.loadCalls, 2);
    },
  );

  test('không gọi repository khi cố revoke current session', () async {
    bloc.add(const LoadDeviceSessionsRequested('test-user'));
    await bloc.stream.firstWhere((state) => state is DeviceSessionsLoaded);
    final failure = bloc.stream.firstWhere(
      (state) => state is DeviceSessionActionFailure,
    );

    bloc.add(
      const RevokeDeviceSessionRequested(
        userId: 'test-user',
        registrationId: '10000000-0000-4000-8000-000000000001',
      ),
    );

    expect((await failure as DeviceSessionActionFailure).devices, [
      current,
      other,
    ]);
    expect(repository.revokeCalls, 0);
  });

  test('revoke riêng target giữ current và loại target sau success', () async {
    bloc.add(const LoadDeviceSessionsRequested('test-user'));
    await bloc.stream.firstWhere((state) => state is DeviceSessionsLoaded);
    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<DeviceSessionRevoking>().having(
          (state) => state.registrationId,
          'registrationId',
          other.registrationId,
        ),
        isA<DeviceSessionRevocationSuccess>().having(
          (state) => state.devices,
          'devices',
          [current],
        ),
      ]),
    );

    bloc.add(
      RevokeDeviceSessionRequested(
        userId: 'test-user',
        registrationId: other.registrationId,
      ),
    );

    await states;
    expect(repository.revokeCalls, 1);
    expect(repository.lastRegistrationId, other.registrationId);
  });

  test('revoke failure giữ nguyên list để retry/reload', () async {
    repository.revokeResult = const Left(
      ServerFailure('TEST_ONLY trạng thái revoke chưa xác định'),
    );
    bloc.add(const LoadDeviceSessionsRequested('test-user'));
    await bloc.stream.firstWhere((state) => state is DeviceSessionsLoaded);
    final failure = bloc.stream.firstWhere(
      (state) => state is DeviceSessionActionFailure,
    );

    bloc.add(
      RevokeDeviceSessionRequested(
        userId: 'test-user',
        registrationId: other.registrationId,
      ),
    );

    final state = await failure as DeviceSessionActionFailure;
    expect(state.devices, [current, other]);
    expect(state.message, contains('chưa xác định'));
  });

  test('string representation không lộ user/registration identifier', () {
    const userId = 'sensitive-user-id';
    const registrationId = 'sensitive-registration-id';
    expect(
      const LoadDeviceSessionsRequested(userId).toString(),
      isNot(contains(userId)),
    );
    expect(
      const RevokeDeviceSessionRequested(
        userId: userId,
        registrationId: registrationId,
      ).toString(),
      allOf(isNot(contains(userId)), isNot(contains(registrationId))),
    );
    expect(
      AuthenticatorDeviceSession(
        registrationId: registrationId,
        displayName: 'Sensitive label',
        platform: 'linux',
        registeredAt: DateTime.utc(2026),
        lastSeenAt: DateTime.utc(2026),
        isCurrent: false,
      ).toString(),
      allOf(
        isNot(contains(registrationId)),
        isNot(contains('Sensitive label')),
      ),
    );
    expect(
      DeviceSessionsLoaded(userId, [current]).toString(),
      isNot(contains(userId)),
    );
  });
}

class _FakeDeviceSessionRepository
    implements AuthenticatorDeviceSessionRepository {
  final List<AuthenticatorDeviceSession> devices;
  Completer<Either<Failure, List<AuthenticatorDeviceSession>>>? pendingLoad;
  Either<Failure, void> revokeResult = const Right(null);
  int loadCalls = 0;
  int revokeCalls = 0;
  String? lastUserId;
  String? lastRegistrationId;

  _FakeDeviceSessionRepository(this.devices);

  @override
  Future<Either<Failure, List<AuthenticatorDeviceSession>>> load({
    required String userId,
  }) async {
    loadCalls += 1;
    lastUserId = userId;
    final pending = pendingLoad;
    pendingLoad = null;
    return pending?.future ?? Right(devices);
  }

  @override
  Future<Either<Failure, void>> revoke({
    required String userId,
    required String registrationId,
  }) async {
    revokeCalls += 1;
    lastUserId = userId;
    lastRegistrationId = registrationId;
    return revokeResult;
  }
}
