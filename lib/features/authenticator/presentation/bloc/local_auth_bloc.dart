import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/core/platform/platform_capabilities.dart';
import 'package:local_auth/local_auth.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'local_auth_event.dart';
part 'local_auth_state.dart';

// Key must match the one used in SettingsBloc
const String _biometricPrefKey = 'biometric_enabled';

@lazySingleton
class LocalAuthBloc extends Bloc<LocalAuthEvent, LocalAuthState> {
  final LocalAuthentication auth;
  final SharedPreferences sharedPreferences;

  LocalAuthBloc({required this.auth, required this.sharedPreferences})
    : super(LocalAuthInitial()) {
    on<CheckLocalAuth>(_onCheckLocalAuth);
    on<Authenticate>(_onAuthenticate);
    on<RelockAppRequested>(_onRelockAppRequested);
    on<ResetAuthStatus>(_onResetAuthStatus);
  }

  Future<void> _onCheckLocalAuth(
    CheckLocalAuth event,
    Emitter<LocalAuthState> emit,
  ) async {
    if (state is LocalAuthSuccess) {
      return;
    }
    if (!PlatformCapabilities.supportsLocalAuthentication) {
      emit(LocalAuthSuccess());
      return;
    }

    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      final bool isBiometricEnabled =
          sharedPreferences.getBool(_biometricPrefKey) ?? false;

      if (canAuthenticate && isBiometricEnabled) {
        emit(LocalAuthRequired());
      } else {
        emit(LocalAuthSuccess());
      }
    } catch (e) {
      emit(
        LocalAuthError(
          'Error checking local authentication availability: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onAuthenticate(
    Authenticate event,
    Emitter<LocalAuthState> emit,
  ) async {
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Xác thực để truy cập các tài khoản của bạn',
        persistAcrossBackgrounding: true,
      );

      if (didAuthenticate) {
        emit(LocalAuthSuccess());
      } else {
        emit(LocalAuthRequired());
      }
    } on LocalAuthException catch (error) {
      if (error.code == LocalAuthExceptionCode.userCanceled ||
          error.code == LocalAuthExceptionCode.systemCanceled) {
        emit(LocalAuthRequired());
        return;
      }
      emit(
        LocalAuthError(
          'Không thể xác thực trên thiết bị (${error.code.name}).',
        ),
      );
    } catch (e) {
      emit(LocalAuthError('Đã xảy ra lỗi không mong muốn khi xác thực.'));
    }
  }

  // Handler for the new event to force re-locking
  Future<void> _onRelockAppRequested(
    RelockAppRequested event,
    Emitter<LocalAuthState> emit,
  ) async {
    if (!PlatformCapabilities.supportsLocalAuthentication) {
      emit(LocalAuthSuccess());
      return;
    }

    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      final bool isBiometricEnabled =
          sharedPreferences.getBool(_biometricPrefKey) ?? false;

      if (canAuthenticate && isBiometricEnabled) {
        emit(LocalAuthRequired());
      } else {
        emit(LocalAuthSuccess());
      }
    } catch (e) {
      emit(LocalAuthError('Error during relock request: ${e.toString()}'));
    }
  }

  void _onResetAuthStatus(ResetAuthStatus event, Emitter<LocalAuthState> emit) {
    if (state is! LocalAuthInitial && state is! LocalAuthRequired) {
      emit(LocalAuthInitial());
    }
  }
}
