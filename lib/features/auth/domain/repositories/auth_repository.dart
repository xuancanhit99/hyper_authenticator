// lib/features/auth/domain/repositories/auth_repository.dart
import 'package:fpdart/fpdart.dart'; // For Either
import 'package:hyper_authenticator/core/error/failures.dart'; // Your custom Failure class
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart'; // Import UserEntity

abstract class AuthRepository {
  UserEntity? get currentUserEntity;

  Stream<UserEntity?> get authEntityChanges;

  Future<Either<Failure, UserEntity?>> getCurrentUserEntity();

  Future<Either<Failure, UserEntity>> signInWithPassword({
    required String email,
    required String password,
  });

  Future<Either<Failure, UserEntity>> signUpWithPassword({
    required String name, // Keep name for metadata
    required String email,
    required String password,
    // String? phone, // REMOVE phone from initial sign up
  });

  Future<Either<Failure, void>> recoverPassword(String email);

  Future<Either<Failure, void>> signOut();

  // Added method for updating password
  Future<Either<Failure, void>> updatePassword(String newPassword);
}
