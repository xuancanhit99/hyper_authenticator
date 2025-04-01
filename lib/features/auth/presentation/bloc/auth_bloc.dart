import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

part 'auth_event.dart';

part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<AuthLoginEvent>(_handleLogin);
    on<AuthRegisterEvent>(_handleRegister);
  }

  Future<void> _handleLogin(
    AuthLoginEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: event.email,
        password: event.password,
      );

      if (response.user != null) {
        emit(AuthAuthenticated(response.user!));
      } else {
        emit(AuthError('Login failed'));
      }
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _handleRegister(
    AuthRegisterEvent event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: event.email,
        password: event.password,
      );

      if (response.user != null) {
        emit(AuthAuthenticated(response.user!));
      } else {
        emit(AuthError('Registration failed'));
      }
    } on AuthException catch (e) {
      emit(AuthError(e.message));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }
}
