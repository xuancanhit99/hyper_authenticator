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
    required String email,
    required String password,
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
          'Đăng nhập thất bại: thông tin đăng nhập không hợp lệ hoặc không tìm thấy người dùng.',
        );
      }
      return response.user!;
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException('Đã xảy ra lỗi không mong đợi khi đăng nhập.');
    }
  }

  @override
  Future<User> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabaseClient.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null && response.session == null) {
        throw const AuthServerException('Quá trình đăng ký thất bại.');
      }
      if (response.user == null) {
        if (response.session != null) {
          throw const AuthServerException(
            'Đăng ký hoàn tất nhưng response thiếu dữ liệu người dùng.',
          );
        } else {
          throw const AuthServerException(
            'Đăng ký thất bại: server không trả về người dùng hoặc session.',
          );
        }
      }
      return response.user!;
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException('Đã xảy ra lỗi không mong đợi khi đăng ký.');
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
        'Đã xảy ra lỗi không mong đợi khi khôi phục mật khẩu.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabaseClient.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      throw ServerException('Đã xảy ra lỗi khi đăng xuất.');
    }
  }

  @override
  Future<void> revokeOtherSessions() async {
    try {
      await _supabaseClient.auth.signOut(scope: SignOutScope.others);
    } on AuthException catch (e) {
      throw AuthServerException(e.message);
    } catch (_) {
      throw ServerException('Đã xảy ra lỗi khi thu hồi các session khác.');
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
        'Đã xảy ra lỗi không mong đợi khi cập nhật mật khẩu.',
      );
    }
  }
}
