// lib/features/auth/presentation/bloc/auth_bloc.dart
import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';

part 'auth_event.dart';
part 'auth_state.dart';

@lazySingleton
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
    on<AuthPasswordUpdateRequested>(_onPasswordUpdateRequested);
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
    // Supabase can deliver a previously queued null session event after a
    // successful password sign-in. Reconcile it with the repository's current
    // session so a stale stream event cannot overwrite AuthAuthenticated.
    final currentUser = event.user ?? _authRepository.currentUserEntity;
    emit(
      currentUser != null
          ? AuthAuthenticated(currentUser)
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
    result.fold(
      (failure) => emit(AuthFailure(failure.message)),
      (user) => emit(AuthAuthenticated(user)),
    );
  }

  Future<void> _onSignUpRequested(
    AuthSignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await _authRepository.signUpWithPassword(
      email: event.email,
      password: event.password,
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
    await result.fold((failure) {
      emit(AuthFailure(failure.message));
    }, (_) async => emit(AuthUnauthenticated()));
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
}
