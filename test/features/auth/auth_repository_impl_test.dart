import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:hyper_authenticator/features/auth/data/repositories/auth_repository_impl.dart';

void main() {
  test('revoke phiên khác được chuyển qua remote datasource', () async {
    final dataSource = _FakeAuthRemoteDataSource();
    final repository = AuthRepositoryImpl(remoteDataSource: dataSource);

    final result = await repository.revokeOtherSessions();

    expect(result.isRight(), isTrue);
    expect(dataSource.revokeCalls, 1);
  });

  test('lỗi server khi revoke được chuyển thành typed failure', () async {
    final dataSource = _FakeAuthRemoteDataSource(
      error: const ServerException('TEST_ONLY revoke failure'),
    );
    final repository = AuthRepositoryImpl(remoteDataSource: dataSource);

    final result = await repository.revokeOtherSessions();

    expect(result.isLeft(), isTrue);
    result.fold((failure) {
      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'TEST_ONLY revoke failure');
    }, (_) => fail('Expected a failure.'));
    expect(dataSource.revokeCalls, 1);
  });
}

class _FakeAuthRemoteDataSource implements AuthRemoteDataSource {
  final Object? error;
  int revokeCalls = 0;

  _FakeAuthRemoteDataSource({this.error});

  @override
  Future<void> revokeOtherSessions() async {
    revokeCalls += 1;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
