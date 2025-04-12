// lib/features/auth/data/repositories/auth_repository_impl.dart
import 'package:flutter/foundation.dart';
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
    return supabaseUser == null ? null : UserEntity.fromSupabaseUser(supabaseUser);
  }

  @override
  UserEntity? get currentUserEntity => _mapSupabaseUserToEntity(remoteDataSource.currentUser);

  @override
  Stream<UserEntity?> get authEntityChanges => remoteDataSource.authStateChanges.map(_mapSupabaseUserToEntity);

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async {
    try {
      final userEntity = _mapSupabaseUserToEntity(remoteDataSource.currentUser);
      return Right(userEntity);
    } catch (e, s) {
      debugPrint('Unexpected error in getCurrentUserEntity: $e\nStackTrace: $s');
      return Left(ServerFailure('Failed to get current user info. Please try again later.'));
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
    } on ServerException catch(e) {
      return Left(AuthCredentialsFailure(e.message));
    } catch (e, s) {
      debugPrint('Unexpected error in signInWithPassword: $e\nStackTrace: $s');
      return Left(AuthCredentialsFailure('An unexpected error occurred during sign in. Please check your connection or try again later.'));
    }
  }

  @override
  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    try {
      final supabaseUser = await remoteDataSource.signUpWithPassword(
        email: email,
        password: password,
        data: data,
      );
      return Right(UserEntity.fromSupabaseUser(supabaseUser));
    } on AuthServerException catch (e) {
      return Left(AuthServerFailure(e.message));
    } on ServerException catch(e) {
      return Left(AuthServerFailure(e.message));
    } catch (e, s) {
      debugPrint('Unexpected error in signUpWithPassword: $e\nStackTrace: $s');
      return Left(AuthServerFailure('An unexpected error occurred during sign up. Please try again later.'));
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
    } catch (e, s) {
      debugPrint('Unexpected error in recoverPassword: $e\nStackTrace: $s');
      return Left(ServerFailure('An unexpected error occurred while recovering password. Please try again later.'));
    }
  }

  @override
  Future<Either<Failure, void>> signOut() async {
    try {
      await remoteDataSource.signOut();
      return const Right(null);
    } catch (e, s) {
      debugPrint('Unexpected error in signOut: $e\nStackTrace: $s');
      return Left(ServerFailure('Failed to sign out. Please check your connection or try again later.'));
    }
  }
}