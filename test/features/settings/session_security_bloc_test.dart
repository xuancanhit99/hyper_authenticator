import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/session_security_bloc.dart';

void main() {
  late _FakeAuthRepository repository;
  late SessionSecurityBloc bloc;

  setUp(() {
    repository = _FakeAuthRepository();
    bloc = SessionSecurityBloc(repository);
  });

  tearDown(() async {
    await bloc.close();
  });

  test('revoke phiên khác giữ flow thành công tách khỏi AuthBloc', () async {
    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<SessionSecurityInProgress>(),
        isA<SessionSecuritySuccess>(),
      ]),
    );

    bloc.add(const RevokeOtherSessionsRequested());

    await states;
    expect(repository.revokeCalls, 1);
  });

  test('lỗi revoke được giữ trong state để UI cho phép retry', () async {
    repository.revokeResult = const Left(
      ServerFailure('TEST_ONLY session revoke failure'),
    );
    final states = expectLater(
      bloc.stream,
      emitsInOrder([
        isA<SessionSecurityInProgress>(),
        isA<SessionSecurityFailure>().having(
          (state) => state.message,
          'message',
          'TEST_ONLY session revoke failure',
        ),
      ]),
    );

    bloc.add(const RevokeOtherSessionsRequested());

    await states;
    expect(repository.revokeCalls, 1);
  });

  test('hai event đồng thời chỉ tạo một remote revoke', () async {
    final pendingResult = Completer<Either<Failure, void>>();
    repository.pendingResult = pendingResult;
    final inProgress = bloc.stream.firstWhere(
      (state) => state is SessionSecurityInProgress,
    );

    bloc
      ..add(const RevokeOtherSessionsRequested())
      ..add(const RevokeOtherSessionsRequested());

    await inProgress;
    await Future<void>.delayed(Duration.zero);
    expect(repository.revokeCalls, 1);

    pendingResult.complete(const Right(null));
    await bloc.stream.firstWhere((state) => state is SessionSecuritySuccess);
    expect(repository.revokeCalls, 1);
  });
}

class _FakeAuthRepository implements AuthRepository {
  Either<Failure, void> revokeResult = const Right(null);
  Completer<Either<Failure, void>>? pendingResult;
  int revokeCalls = 0;

  @override
  Future<Either<Failure, void>> revokeOtherSessions() async {
    revokeCalls += 1;
    final pending = pendingResult;
    if (pending != null) {
      return pending.future;
    }
    return revokeResult;
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
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async =>
      throw UnimplementedError();
}
