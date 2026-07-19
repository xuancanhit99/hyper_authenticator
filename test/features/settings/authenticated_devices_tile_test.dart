import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';
import 'package:hyper_authenticator/features/settings/domain/repositories/authenticator_device_session_repository.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/device_session_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/authenticated_devices_tile.dart';

void main() {
  const user = UserEntity(id: 'test-user', email: 'user@example.invalid');
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

  testWidgets('list phân biệt current và xác nhận trước revoke target', (
    tester,
  ) async {
    final repository = _FakeDeviceSessionRepository([current, other]);
    final bloc = DeviceSessionBloc(repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(
          home: Scaffold(body: AuthenticatedDevicesTile(currentUser: user)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.loadCalls, 1);
    expect(find.textContaining('2 phiên đã nhận diện'), findsOneWidget);
    await tester.tap(find.text('Thiết bị đã đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.text('Hiện tại'), findsOneWidget);
    expect(find.text('Hyper Authenticator trên Windows'), findsOneWidget);
    await tester.tap(
      find.byTooltip('Đăng xuất Hyper Authenticator trên Windows'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Đăng xuất phiên thiết bị?'), findsOneWidget);
    expect(find.textContaining('Local TOTP'), findsOneWidget);
    expect(repository.revokeCalls, 0);
    await tester.tap(find.text('Đăng xuất thiết bị'));
    await tester.pumpAndSettle();

    expect(repository.revokeCalls, 1);
    expect(repository.lastRegistrationId, other.registrationId);
    expect(find.text('Hyper Authenticator trên Windows'), findsNothing);
    expect(find.text('Hyper Authenticator trên macOS'), findsOneWidget);
  });

  testWidgets('load failure cho phép retry từ tile', (tester) async {
    final repository = _FakeDeviceSessionRepository(const []);
    repository.loadResult = const Left(
      ServerFailure('TEST_ONLY không tải được device registry'),
    );
    final bloc = DeviceSessionBloc(repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(
          home: Scaffold(body: AuthenticatedDevicesTile(currentUser: user)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('TEST_ONLY không tải được device registry'),
      findsOneWidget,
    );
    repository.loadResult = Right([current]);
    await tester.tap(find.text('Thiết bị đã đăng nhập'));
    await tester.pumpAndSettle();

    expect(repository.loadCalls, 2);
    expect(find.textContaining('1 phiên đã nhận diện'), findsOneWidget);
  });

  testWidgets('đổi account không render state registry của user trước', (
    tester,
  ) async {
    final repository = _FakeDeviceSessionRepository([current, other]);
    final bloc = DeviceSessionBloc(repository);
    addTearDown(bloc.close);

    Widget app(UserEntity currentUser) => BlocProvider.value(
      value: bloc,
      child: MaterialApp(
        home: Scaffold(
          body: AuthenticatedDevicesTile(currentUser: currentUser),
        ),
      ),
    );

    await tester.pumpWidget(app(user));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 phiên đã nhận diện'), findsOneWidget);

    await tester.pumpWidget(
      app(const UserEntity(id: 'other-user', email: 'other@example.invalid')),
    );

    expect(find.textContaining('2 phiên đã nhận diện'), findsNothing);
    expect(find.text('Đang đăng ký phiên hiện tại...'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(repository.lastUserId, 'other-user');
  });
}

class _FakeDeviceSessionRepository
    implements AuthenticatorDeviceSessionRepository {
  Either<Failure, List<AuthenticatorDeviceSession>> loadResult;
  Either<Failure, void> revokeResult = const Right(null);
  int loadCalls = 0;
  int revokeCalls = 0;
  String? lastRegistrationId;
  String? lastUserId;

  _FakeDeviceSessionRepository(List<AuthenticatorDeviceSession> devices)
    : loadResult = Right(devices);

  @override
  Future<Either<Failure, List<AuthenticatorDeviceSession>>> load({
    required String userId,
  }) async {
    loadCalls += 1;
    lastUserId = userId;
    return loadResult;
  }

  @override
  Future<Either<Failure, void>> revoke({
    required String userId,
    required String registrationId,
  }) async {
    revokeCalls += 1;
    lastRegistrationId = registrationId;
    return revokeResult;
  }
}
