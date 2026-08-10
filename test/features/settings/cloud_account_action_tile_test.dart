import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/cloud_account_action_tile.dart';

void main() {
  const user = UserEntity(
    id: '00000000-0000-4000-8000-000000000001',
    email: 'test-only@example.invalid',
    name: 'TEST_ONLY User',
  );

  testWidgets('khách có thể mở Login rồi quay về Settings', (tester) async {
    final repository = _FakeAuthRepository();
    final authBloc = AuthBloc(repository);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) =>
              const Scaffold(body: CloudAccountActionTile(currentUser: null)),
        ),
        GoRoute(
          path: '/login',
          builder: (_, state) => Scaffold(
            body: Text(
              'Login returnTo=${state.uri.queryParameters['returnTo']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(() async {
      router.dispose();
      await authBloc.close();
      await repository.close();
    });

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Đăng nhập để đồng bộ'));
    await tester.pumpAndSettle();

    expect(find.text('Login returnTo=/settings'), findsOneWidget);
  });

  testWidgets('đăng xuất cần xác nhận và phát AuthSignOutRequested', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(currentUser: user);
    final authBloc = AuthBloc(repository);
    addTearDown(() async {
      await authBloc.close();
      await repository.close();
    });

    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: authBloc,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: CloudAccountActionTile(currentUser: user)),
        ),
      ),
    );

    await tester.tap(find.text('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(find.text('Xác nhận đăng xuất'), findsOneWidget);
    expect(
      find.textContaining('Các mã đã lưu vẫn được giữ lại'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Đăng xuất'));
    await tester.pumpAndSettle();

    expect(repository.signOutCalls, 1);
    expect(authBloc.state, isA<AuthUnauthenticated>());
  });

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'cloud account action pass a11y ${themeMode.name} ở 320px/200%',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _FakeAuthRepository(currentUser: user);
        final authBloc = AuthBloc(repository);
        addTearDown(() async {
          await authBloc.close();
          await repository.close();
        });

        Future<void> pumpTile(UserEntity? currentUser) => tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: themeMode,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: CloudAccountActionTile(currentUser: currentUser),
                ),
              ),
            ),
          ),
        );

        await pumpTile(null);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await pumpTile(user);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      },
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  final _changes = StreamController<UserEntity?>.broadcast();
  UserEntity? _currentUser;
  int signOutCalls = 0;

  _FakeAuthRepository({this._currentUser});

  Future<void> close() => _changes.close();

  @override
  UserEntity? get currentUserEntity => _currentUser;

  @override
  Stream<UserEntity?> get authEntityChanges => _changes.stream;

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      Right(_currentUser);

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> recoverPassword(String email) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> signOut() async {
    signOutCalls += 1;
    _currentUser = null;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) =>
      throw UnimplementedError();
}
