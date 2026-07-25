// lib/features/auth/presentation/bloc/auth_state.dart
part of 'auth_bloc.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

// When checking auth status or performing login/signup/logout
class AuthLoading extends AuthState {}

// User is logged in
class AuthAuthenticated extends AuthState {
  final UserEntity user; // Changed from Supabase User to UserEntity

  const AuthAuthenticated(this.user);

  @override
  List<Object> get props => [user];

  @override
  String toString() => 'AuthAuthenticated(user: [REDACTED])';
}

// User is not logged in
class AuthUnauthenticated extends AuthState {}

// User has requested a password reset
class AuthPasswordResetEmailSent extends AuthState {}

class AuthSignUpSuccess extends AuthState {}

class AuthPasswordUpdateSuccess extends AuthState {}

// An error occurred during an auth operation
class AuthFailure extends AuthState {
  final String message;
  const AuthFailure(this.message);

  @override
  List<Object> get props => [message];
}
