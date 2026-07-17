import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _FakeAuthRepository repository;
  late AuthBloc bloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = _FakeAuthRepository();
    bloc = AuthBloc(repository, await SharedPreferences.getInstance());
  });

  tearDown(() async {
    await bloc.close();
    await repository.close();
  });

  test(
    'sign in emit trạng thái authenticated không phụ thuộc auth stream',
    () async {
      final states = expectLater(
        bloc.stream,
        emitsInOrder([isA<AuthLoading>(), isA<AuthAuthenticated>()]),
      );

      bloc.add(
        const AuthSignInRequested(
          email: 'user@example.invalid',
          password: 'TEST_ONLY_password',
          rememberMe: false,
        ),
      );

      await states;
    },
  );

  test('sign up yêu cầu xác minh email không mắc kẹt ở loading', () async {
    repository.hasSessionAfterSignUp = false;
    final states = expectLater(
      bloc.stream,
      emitsInOrder([isA<AuthLoading>(), isA<AuthSignUpSuccess>()]),
    );

    bloc.add(
      const AuthSignUpRequested(
        name: 'Test User',
        email: 'user@example.invalid',
        password: 'TEST_ONLY_password',
      ),
    );

    await states;
  });
}

class _FakeAuthRepository implements AuthRepository {
  static const user = UserEntity(
    id: 'test-user',
    email: 'user@example.invalid',
    name: 'Test User',
  );

  final _changes = StreamController<UserEntity?>.broadcast();
  UserEntity? _currentUser;
  bool hasSessionAfterSignUp = true;

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
  }) async {
    _currentUser = user;
    return const Right(user);
  }

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    _currentUser = hasSessionAfterSignUp ? user : null;
    return const Right(user);
  }

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> signOut() async {
    _currentUser = null;
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async =>
      const Right(null);
}
