// lib/features/auth/data/datasources/auth_remote_data_source.dart
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';

abstract class AuthRemoteDataSource {
  User? get currentUser;
  Stream<User?> get authStateChanges;

  Future<User> signInWithPassword({
    required String email,
    required String password,
  });

  Future<User> signUpWithPassword({
    required String email, // Keep email
    required String password,
    // String? phone, // REMOVE phone from initial sign up interface
    Map<String, dynamic>? data, // Keep data for metadata like name
  });

  Future<void> recoverPassword(String email);

  Future<void> signOut();

  Future<void> revokeOtherSessions();

  // Added method for updating password
  Future<void> updatePassword(String newPassword);
}

@LazySingleton(as: AuthRemoteDataSource)
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient _supabaseClient;
  final AppConfig _appConfig;

  AuthRemoteDataSourceImpl(this._supabaseClient, this._appConfig);

  @override
  User? get currentUser => _supabaseClient.auth.currentUser;

  @override
  Stream<User?> get authStateChanges => _supabaseClient.auth.onAuthStateChange
      .map((event) => event.session?.user);

  @override
  Future<User> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.user == null) {
        throw const AuthServerException(
          'Sign in failed: Invalid credentials or user not found.',
        );
      }
      return response.user!;
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException('An unexpected error occurred during sign in.');
    }
  }

  @override
  // Updated signature (removed phone)
  Future<User> signUpWithPassword({
    required String email,
    required String password,
    // String? phone, // REMOVED phone
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _supabaseClient.auth.signUp(
        email: email,
        password: password,
        // phone: phone, // REMOVE phone from the call
        data: data,
      );

      if (response.user == null && response.session == null) {
        throw const AuthServerException('Sign up process failed unexpectedly.');
      }
      if (response.user == null) {
        if (response.session != null) {
          throw const AuthServerException(
            'Sign up completed but user data is missing in response.',
          );
        } else {
          throw const AuthServerException(
            'Sign up process failed: No user or session returned.',
          );
        }
      }
      return response.user!;
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException('An unexpected error occurred during sign up.');
    }
  }

  @override
  Future<void> recoverPassword(String email) async {
    final recoveryUrl = _appConfig.passwordRecoveryUrl;
    if (recoveryUrl == null) {
      throw const AuthServerException(
        'Password recovery chưa được cấu hình cho environment này.',
      );
    }
    try {
      await _supabaseClient.auth.resetPasswordForEmail(
        email,
        redirectTo: recoveryUrl,
      );
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException(
        'An unexpected error occurred during password recovery.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabaseClient.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      throw ServerException('An error occurred during sign out.');
    }
  }

  @override
  Future<void> revokeOtherSessions() async {
    try {
      await _supabaseClient.auth.signOut(scope: SignOutScope.others);
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException('An error occurred while revoking other sessions.');
    }
  }

  // Implementation for updatePassword
  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _supabaseClient.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException(
        'An unexpected error occurred while updating password.',
      );
    }
  }
}
