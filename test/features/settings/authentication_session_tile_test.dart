import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/session_security_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/widgets/authentication_session_tile.dart';

void main() {
  const user = UserEntity(
    id: 'test-user',
    email: 'user@example.invalid',
    name: 'Test User',
  );

  testWidgets('revoke phiên khác cần xác nhận rõ trước khi phát event', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    final bloc = SessionSecurityBloc(repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(
          home: Scaffold(
            body: AuthenticationSessionTile(
              currentUser: user,
              sessionSecurityState: SessionSecurityIdle(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Đăng xuất các phiên khác'));
    await tester.pumpAndSettle();

    expect(find.text('Đăng xuất các phiên khác?'), findsOneWidget);
    expect(find.textContaining('server chặn ngay'), findsOneWidget);
    expect(repository.revokeCalls, 0);

    await tester.tap(find.text('Đăng xuất phiên khác'));
    await tester.pumpAndSettle();

    expect(repository.revokeCalls, 1);
  });

  testWidgets('không cho gửi lại revoke khi operation đang chạy', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    final bloc = SessionSecurityBloc(repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: bloc,
        child: const MaterialApp(
          home: Scaffold(
            body: AuthenticationSessionTile(
              currentUser: user,
              sessionSecurityState: SessionSecurityInProgress(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Đăng xuất các phiên khác'));
    await tester.pump();

    expect(find.text('Đăng xuất các phiên khác?'), findsNothing);
    expect(repository.revokeCalls, 0);
  });

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'session action pass accessibility/contrast ${themeMode.name}',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _FakeAuthRepository();
        final bloc = SessionSecurityBloc(repository);
        addTearDown(bloc.close);

        await tester.pumpWidget(
          BlocProvider.value(
            value: bloc,
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
              home: const Scaffold(
                body: SingleChildScrollView(
                  child: AuthenticationSessionTile(
                    currentUser: user,
                    sessionSecurityState: SessionSecurityIdle(),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(
          find.bySemanticsLabel(RegExp('^Đăng xuất các phiên khác')),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp('^Đăng xuất\n')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(find.text('Đăng xuất các phiên khác'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(repository.revokeCalls, 0);
        expect(find.text('Đăng xuất các phiên khác?'), findsNothing);
        semantics.dispose();
      },
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  int revokeCalls = 0;

  @override
  Future<Either<Failure, void>> revokeOtherSessions() async {
    revokeCalls += 1;
    return const Right(null);
  }

  @override
  UserEntity? get currentUserEntity => null;

  @override
  Stream<UserEntity?> get authEntityChanges => const Stream.empty();

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> signOut() async => throw UnimplementedError();

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String name,
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async =>
      throw UnimplementedError();
}
