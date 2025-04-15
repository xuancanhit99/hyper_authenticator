// lib/features/auth/presentation/bloc/auth_bloc.dart
import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Import FlutterSecureStorage
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

// Key must match the one used in SettingsBloc and LocalAuthBloc
const String _biometricPrefKey = 'biometric_enabled';
const String _rememberedEmailKey =
    'remembered_email'; // Key for remembered email

@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final SharedPreferences _sharedPreferences; // Add dependency
  final FlutterSecureStorage _secureStorage; // Add dependency
  StreamSubscription<UserEntity?>? _authEntitySubscription;

  AuthBloc(
    this._authRepository,
    this._sharedPreferences, // Add to constructor
    this._secureStorage, // Add to constructor
  ) : super(AuthInitial()) {
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
    debugPrint("Auth Entity Changed: ${event.user?.email ?? 'Logged Out'}");
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
    result.fold((failure) => emit(AuthFailure(failure.message)), (userEntity) {
      debugPrint(
        "Sign In successful for ${userEntity.email}, waiting for stream update.",
      );
      // Handle Remember Me
      if (event.rememberMe) {
        _sharedPreferences.setString(_rememberedEmailKey, event.email);
      } else {
        _sharedPreferences.remove(_rememberedEmailKey);
      }
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
    result.fold((failure) => emit(AuthFailure(failure.message)), (userEntity) {
      debugPrint(
        "Sign Up successful for ${userEntity.email}, waiting for stream update.",
      );
    });
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
    result.fold(
      (failure) {
        debugPrint("Sign Out failed: ${failure.message}");
        emit(AuthFailure(failure.message));
      },
      (_) async {
        // Add async here
        debugPrint(
          "Sign Out successful, disabling biometrics and waiting for stream update.",
        );
        // Disable biometric preference on successful sign out
        await _sharedPreferences.setBool(_biometricPrefKey, false);
        // Clear secure storage on successful sign out
        await _secureStorage.deleteAll();
        debugPrint("Cleared secure storage.");
        // Also clear remembered email on sign out
        await _sharedPreferences.remove(_rememberedEmailKey);
        // The stream update will handle the state change to AuthUnauthenticated
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
    result.fold((failure) => emit(AuthFailure(failure.message)), (_) {
      // Password updated successfully. We might rely on AuthUserChanged
      // or emit a specific success state if needed for UI feedback before navigation.
      // For now, just print and assume navigation happens in UI based on state change.
      debugPrint("Password update successful.");
      // Optionally emit a specific state like AuthPasswordUpdateSuccess
      // emit(AuthPasswordUpdateSuccess());
      // Or rely on the user stream update if the session changes/refreshes.
    });
  }

  Future<void> _onLoadRememberedUser(
    LoadRememberedUser event,
    Emitter<AuthState> emit,
  ) async {
    // Only load if the current state is initial (or unauthenticated)
    if (state is AuthInitial || state is AuthUnauthenticated) {
      final rememberedEmail = _sharedPreferences.getString(_rememberedEmailKey);
      if (rememberedEmail != null) {
        // Emit AuthInitial with the remembered email
        // This allows the LoginPage to pre-fill the email field
        emit(AuthInitial(rememberedEmail: rememberedEmail));
      } else {
        // If no email is remembered, just stay in the current state or emit default AuthInitial
        if (state is! AuthInitial) {
          emit(
            const AuthInitial(),
          ); // Ensure it's AuthInitial if nothing is loaded
        }
      }
    }
  }
}
