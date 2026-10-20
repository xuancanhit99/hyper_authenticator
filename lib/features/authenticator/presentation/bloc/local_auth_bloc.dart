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
  int _lockEpoch = 0;

  LocalAuthBloc({required this.auth, required this.sharedPreferences})
    : super(LocalAuthInitial()) {
    on<CheckLocalAuth>(_onCheckLocalAuth);
    on<Authenticate>(_onAuthenticate);
    on<ResetAuthStatus>(_onResetAuthStatus);
  }

  Future<void> _onCheckLocalAuth(
    CheckLocalAuth event,
    Emitter<LocalAuthState> emit,
  ) async {
    if (state is LocalAuthSuccess) {
      return;
    }
    final epoch = _lockEpoch;

    try {
      final enabled = sharedPreferences.getBool(_biometricPrefKey) ?? false;
      if (!enabled) {
        emit(LocalAuthSuccess());
        return;
      }
      if (!PlatformCapabilities.supportsLocalAuthentication) {
        emit(
          const LocalAuthError(
            'Khóa ứng dụng chưa khả dụng trên thiết bị. Hãy thử lại.',
          ),
        );
        return;
      }
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (epoch != _lockEpoch) return;
      if (canAuthenticate) {
        emit(LocalAuthRequired());
      } else {
        emit(
          const LocalAuthError(
            'Khóa ứng dụng chưa khả dụng trên thiết bị. Hãy thử lại.',
          ),
        );
      }
    } catch (_) {
      if (epoch != _lockEpoch) return;
      emit(
        const LocalAuthError('Không thể kiểm tra khóa ứng dụng. Hãy thử lại.'),
      );
    }
  }

  Future<void> _onAuthenticate(
    Authenticate event,
    Emitter<LocalAuthState> emit,
  ) async {
    final epoch = _lockEpoch;
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Xác thực để mở các mã của bạn',
        persistAcrossBackgrounding: true,
      );

      if (epoch != _lockEpoch) return;
      if (didAuthenticate) {
        emit(LocalAuthSuccess());
      } else {
        emit(LocalAuthRequired());
      }
    } on LocalAuthException catch (error) {
      if (epoch != _lockEpoch) return;
      if (error.code == LocalAuthExceptionCode.userCanceled ||
          error.code == LocalAuthExceptionCode.systemCanceled) {
        emit(LocalAuthRequired());
        return;
      }
      emit(
        const LocalAuthError('Không thể xác thực trên thiết bị. Hãy thử lại.'),
      );
    } catch (_) {
      if (epoch != _lockEpoch) return;
      emit(
        const LocalAuthError('Không thể xác thực trên thiết bị. Hãy thử lại.'),
      );
    }
  }

  void _onResetAuthStatus(ResetAuthStatus event, Emitter<LocalAuthState> emit) {
    _lockEpoch++;
    if (state is! LocalAuthInitial && state is! LocalAuthRequired) {
      emit(LocalAuthInitial());
    }
  }
}
