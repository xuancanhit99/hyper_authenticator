// lib/features/auth/presentation/bloc/auth_bloc.dart
import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

@injectable
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  StreamSubscription<UserEntity?>? _authEntitySubscription;

  AuthBloc(this._authRepository) : super(AuthInitial()) {
    _authEntitySubscription = _authRepository.authEntityChanges.listen(
          (userEntity) => add(_AuthUserChanged(userEntity)),
    );

    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthSignInRequested>(_onSignInRequested);
    on<AuthSignUpRequested>(_onSignUpRequested);
    on<AuthSignOutRequested>(_onSignOutRequested);
    on<_AuthUserChanged>(_onAuthUserChanged);
    on<AuthRecoverPasswordRequested>(_onRecoverPasswordRequested);
  }

  @override
  Future<void> close() {
    _authEntitySubscription?.cancel();
    return super.close();
  }

  Future<void> _onAuthCheckRequested(
      AuthCheckRequested event, Emitter<AuthState> emit) async {
    final result = await _authRepository.getCurrentUserEntity();
    result.fold(
          (failure) => emit(AuthFailure(failure.message)),
          (userEntity) => emit(userEntity != null ? AuthAuthenticated(userEntity) : AuthUnauthenticated()),
    );
  }

  void _onAuthUserChanged(_AuthUserChanged event, Emitter<AuthState> emit) {
    debugPrint("Auth Entity Changed: ${event.user?.email ?? 'Logged Out'}");
    emit(event.user != null ? AuthAuthenticated(event.user!) : AuthUnauthenticated());
  }


  Future<void> _onSignInRequested(
      AuthSignInRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final result = await _authRepository.signInWithPassword(
      email: event.email,
      password: event.password,
    );
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (userEntity) {
        debugPrint("Sign In successful for ${userEntity.email}, waiting for stream update.");
      },
    );
  }

  Future<void> _onSignUpRequested(
      AuthSignUpRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final result = await _authRepository.signUpWithPassword(
      email: event.email,
      password: event.password,
    );
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (userEntity) {
        debugPrint("Sign Up successful for ${userEntity.email}, waiting for stream update.");
      },
    );
  }

  Future<void> _onRecoverPasswordRequested(
      AuthRecoverPasswordRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final result = await _authRepository.recoverPassword(event.email);
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (_) => emit(AuthPasswordResetEmailSent()),
    );
  }

  Future<void> _onSignOutRequested(
      AuthSignOutRequested event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final result = await _authRepository.signOut();
    result.fold(
      (failure) {
        debugPrint("Sign Out failed: ${failure.message}");
        emit(AuthFailure(failure.message));
      },
      (_) {
        debugPrint("Sign Out successful, waiting for stream update.");
      },
    );
  }
}