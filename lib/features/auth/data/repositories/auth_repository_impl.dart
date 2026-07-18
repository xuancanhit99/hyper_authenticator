// lib/features/auth/data/repositories/auth_repository_impl.dart
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:hyper_authenticator/core/error/exceptions.dart';

@LazySingleton(as: AuthRepository)
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl({required this.remoteDataSource});

  UserEntity? _mapSupabaseUserToEntity(User? supabaseUser) {
    return supabaseUser == null
        ? null
        : UserEntity.fromSupabaseUser(supabaseUser);
  }

  @override
  UserEntity? get currentUserEntity =>
      _mapSupabaseUserToEntity(remoteDataSource.currentUser);

  @override
  Stream<UserEntity?> get authEntityChanges =>
      remoteDataSource.authStateChanges.map(_mapSupabaseUserToEntity);

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async {
    try {
      final userEntity = _mapSupabaseUserToEntity(remoteDataSource.currentUser);
      return Right(userEntity);
    } catch (_) {
      return Left(
        ServerFailure(
          'Không thể lấy thông tin người dùng hiện tại. Vui lòng thử lại sau.',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final supabaseUser = await remoteDataSource.signInWithPassword(
        email: email,
        password: password,
      );
      return Right(UserEntity.fromSupabaseUser(supabaseUser));
    } on AuthServerException catch (e) {
      return Left(AuthCredentialsFailure(e.message));
    } on ServerException catch (e) {
      return Left(AuthCredentialsFailure(e.message));
    } catch (_) {
      return Left(
        AuthCredentialsFailure(
          'Đăng nhập gặp lỗi không mong đợi. Hãy kiểm tra kết nối hoặc thử lại sau.',
        ),
      );
    }
  }

  @override
  // Updated signature (removed phone)
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String name,
    required String email,
    required String password,
    // String? phone, // REMOVED phone
  }) async {
    try {
      // Construct data map for user_metadata
      final Map<String, dynamic> userData = {'name': name};
      // If phone is provided and not empty, add it.
      // Note: Supabase signUp might take phone at top level, adjust if remoteDataSource expects that.
      // Assuming remoteDataSource handles phone separately or within data for now.
      // Let's assume remoteDataSource.signUpWithPassword is updated to take name/phone or uses data map correctly.
      // For simplicity, passing name in data. Phone handling might need adjustment in DataSource.
      final supabaseUser = await remoteDataSource.signUpWithPassword(
        email: email,
        password: password,
        data: userData, // Pass name in data map
        // phone: phone, // REMOVE phone from the call
      );
      return Right(UserEntity.fromSupabaseUser(supabaseUser));
    } on AuthServerException catch (e) {
      return Left(AuthServerFailure(e.message));
    } on ServerException catch (e) {
      return Left(AuthServerFailure(e.message));
    } catch (_) {
      return Left(
        AuthServerFailure(
          'Đăng ký gặp lỗi không mong đợi. Vui lòng thử lại sau.',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, void>> recoverPassword(String email) async {
    try {
      await remoteDataSource.recoverPassword(email);
      return const Right(null);
    } on AuthServerException catch (e) {
      return Left(AuthServerFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return Left(
        ServerFailure(
          'Khôi phục mật khẩu gặp lỗi không mong đợi. Vui lòng thử lại sau.',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, void>> signOut() async {
    try {
      await remoteDataSource.signOut();
      return const Right(null);
    } catch (_) {
      return Left(
        ServerFailure(
          'Không thể đăng xuất. Hãy kiểm tra kết nối hoặc thử lại sau.',
        ),
      );
    }
  }

  @override
  Future<Either<Failure, void>> revokeOtherSessions() async {
    try {
      await remoteDataSource.revokeOtherSessions();
      return const Right(null);
    } on AuthServerException catch (e) {
      return Left(AuthServerFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return Left(
        ServerFailure(
          'Không thể thu hồi các session khác. Hãy kiểm tra kết nối hoặc thử lại sau.',
        ),
      );
    }
  }

  // Implementation for the new updatePassword method
  @override
  Future<Either<Failure, void>> updatePassword(String newPassword) async {
    try {
      // Assuming remoteDataSource has an updatePassword method
      await remoteDataSource.updatePassword(newPassword);
      return const Right(null);
    } on AuthServerException catch (e) {
      return Left(AuthServerFailure(e.message));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (_) {
      return Left(
        ServerFailure(
          'Cập nhật mật khẩu gặp lỗi không mong đợi. Vui lòng thử lại sau.',
        ),
      );
    }
  }
}
