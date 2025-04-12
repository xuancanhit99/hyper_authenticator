// lib/features/auth/data/datasources/auth_remote_data_source.dart
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';

abstract class AuthRemoteDataSource {
  User? get currentUser;
  Stream<User?> get authStateChanges;

  Future<User> signInWithPassword({
    required String email,
    required String password,
  });

  Future<User> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  });

  Future<void> recoverPassword(String email);

  Future<void> signOut();
}

@LazySingleton(as: AuthRemoteDataSource)
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient _supabaseClient;

  AuthRemoteDataSourceImpl(this._supabaseClient);

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
        throw const AuthServerException('Sign in failed: Invalid credentials or user not found.');
      }
      return response.user!;
    } on AuthException catch (e) {
      debugPrint('Supabase SignIn AuthException: ${e.message}');
      throw AuthServerException(e.message);
    } catch (e, s) {
      debugPrint('Unknown SignIn Error: $e\nStackTrace: $s');
      throw ServerException('An unexpected error occurred during sign in.');
    }
  }

  @override
  Future<User> signUpWithPassword({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _supabaseClient.auth.signUp(
        email: email,
        password: password,
        data: data,
      );

      if (response.user == null && response.session == null) {
         throw const AuthServerException('Sign up process failed unexpectedly.');
      }
       if (response.user == null) {
         if (response.session != null) {
            debugPrint('SignUp successful (session created), but user object is null. Email verification likely required.');
             throw const AuthServerException('Sign up completed but user data is missing in response.');

         } else {
            throw const AuthServerException('Sign up process failed: No user or session returned.');
         }

      }
       return response.user!;


    } on AuthException catch (e) {
       debugPrint('Supabase SignUp AuthException: ${e.message}');
       throw AuthServerException(e.message);
    } catch (e, s) {
       debugPrint('Unknown SignUp Error: $e\nStackTrace: $s');
       throw ServerException('An unexpected error occurred during sign up.');
    }
  }

  @override
  Future<void> recoverPassword(String email) async {
    try {
      await _supabaseClient.auth.resetPasswordForEmail(email);
    } on AuthException catch (e) {
      debugPrint("Supabase RecoverPassword Error: ${e.message}");
      throw AuthServerException(e.message);
    } catch (e, s) {
      debugPrint("Unknown RecoverPassword Error: $e\nStackTrace: $s");
      throw ServerException('An unexpected error occurred during password recovery.');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabaseClient.auth.signOut();
    } catch (e, s) {
       debugPrint("Supabase SignOut Error: $e\nStackTrace: $s");
       throw ServerException('An error occurred during sign out.');
    }
  }
}