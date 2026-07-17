// lib/features/auth/presentation/bloc/auth_bloc.dart
import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

// Key must match the one used in SettingsBloc and LocalAuthBloc
const String _biometricPrefKey = 'biometric_enabled';
const String _rememberedEmailKey =
    'remembered_email'; // Key for remembered email
const String _rememberedMeStateKey =
    'remembered_me_state'; // Key for remember me checkbox state

@lazySingleton
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final SharedPreferences _sharedPreferences;
  StreamSubscription<UserEntity?>? _authEntitySubscription;

  AuthBloc(this._authRepository, this._sharedPreferences)
    : super(AuthInitial()) {
    _authEntitySubscription = _authRepository.authEntityChanges.listen(
      (userEntity) => add(_AuthUserChanged(userEntity)),
    );

    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthSignInRequested>(_onSignInRequested);
    on<AuthSignUpRequested>(_onSignUpRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<_AuthUserChanged>(_onAuthUserChanged);
    on<AuthRecoverPasswordRequested>(_onRecoverPasswordRequested);
    on<AuthPasswordUpdateRequested>(_onPasswordUpdateRequested);
    on<LoadRememberedUser>(_onLoadRememberedUser); // Add handler for new event
  }

  @override
  Future<void> close() {
    _authEntitySubscription?.cancel();
    return super.close();
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    final result = await _authRepository.getCurrentUserEntity();
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (userEntity) => emit(
        userEntity != null
            ? AuthAuthenticated(userEntity)
            : AuthUnauthenticated(),
      ),
    );
  }

  void _onAuthUserChanged(_AuthUserChanged event, Emitter<AuthState> emit) {
    emit(
      event.user != null
          ? AuthAuthenticated(event.user!)
          : AuthUnauthenticated(),
    );
  }

  Future<void> _onSignInRequested(
    AuthSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await _authRepository.signInWithPassword(
      email: event.email,
      password: event.password,
    );
    await result.fold((failure) async => emit(AuthFailure(failure.message)), (
      user,
    ) async {
      if (event.rememberMe) {
        await _sharedPreferences.setString(_rememberedEmailKey, event.email);
        await _sharedPreferences.setBool(_rememberedMeStateKey, true);
      } else {
        await _sharedPreferences.remove(_rememberedEmailKey);
        await _sharedPreferences.remove(_rememberedMeStateKey);
      }
      emit(AuthAuthenticated(user));
    });
  }

  Future<void> _onSignUpRequested(
    AuthSignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    // Updated (removed phone)
    final result = await _authRepository.signUpWithPassword(
      name: event.name,
      email: event.email,
      password: event.password,
      // phone: event.phone, // REMOVE phone from the call
    );
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (user) => emit(
        _authRepository.currentUserEntity == null
            ? AuthSignUpSuccess()
            : AuthAuthenticated(user),
      ),
    );
  }

  Future<void> _onRecoverPasswordRequested(
    AuthRecoverPasswordRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await _authRepository.recoverPassword(event.email);
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (_) => emit(AuthPasswordResetEmailSent()),
    );
  }

  Future<void> _onSignOutRequested(
    AuthSignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await _authRepository.signOut();
    await result.fold(
      (failure) {
        emit(AuthFailure(failure.message));
      },
      (_) async {
        // Disable biometric preference on successful sign out
        await _sharedPreferences.setBool(_biometricPrefKey, false);
        // Also clear remembered email and state on sign out
        await _sharedPreferences.remove(_rememberedEmailKey);
        await _sharedPreferences.remove(_rememberedMeStateKey);
        // Also clear sync enabled state on sign out
        await _sharedPreferences.remove(
          'sync_enabled',
        ); // Use the key defined in SyncBloc
        emit(AuthUnauthenticated());
      },
    );
  }

  // Handler for password update
  Future<void> _onPasswordUpdateRequested(
    AuthPasswordUpdateRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    // Assuming a new method in the repository
    final result = await _authRepository.updatePassword(event.newPassword);
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (_) => emit(AuthPasswordUpdateSuccess()),
    );
  }

  Future<void> _onLoadRememberedUser(
    LoadRememberedUser event,
    Emitter<AuthState> emit,
  ) async {
    // Only load if the current state is initial (or unauthenticated)
    if (state is AuthInitial || state is AuthUnauthenticated) {
      final rememberedEmail = _sharedPreferences.getString(_rememberedEmailKey);
      final rememberedMeState = _sharedPreferences.getBool(
        _rememberedMeStateKey,
      );

      // Only emit if we have at least an email or a state saved
      // (Though typically they should be saved/removed together)
      if (rememberedEmail != null || rememberedMeState != null) {
        // Emit AuthInitial with both remembered email and state
        // Default rememberedMeState to false if null (e.g., older version)
        emit(
          AuthInitial(
            rememberedEmail: rememberedEmail,
            rememberedMeState: rememberedMeState ?? false,
          ),
        );
      } else {
        // If nothing is remembered, ensure state is default AuthInitial
        if (state is! AuthInitial ||
            (state as AuthInitial).rememberedEmail != null ||
            (state as AuthInitial).rememberedMeState != null) {
          emit(const AuthInitial()); // Reset to default initial state
        }
      }
    }
  }
}
