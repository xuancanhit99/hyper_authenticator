// lib/features/auth/presentation/bloc/auth_event.dart
part of 'auth_bloc.dart'; // Keep this

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class AuthSignInRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthSignInRequested({required this.email, required this.password});

  @override
  List<Object> get props => [email, password];

  @override
  String toString() =>
      'AuthSignInRequested(email: [REDACTED], password: [REDACTED])';
}

class AuthSignUpRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthSignUpRequested({required this.email, required this.password});

  @override
  List<Object?> get props => [email, password];

  @override
  String toString() =>
      'AuthSignUpRequested(email: [REDACTED], password: [REDACTED])';
}

class AuthRecoverPasswordRequested extends AuthEvent {
  final String email;
  const AuthRecoverPasswordRequested(this.email);

  @override
  List<Object> get props => [email];

  @override
  String toString() => 'AuthRecoverPasswordRequested(email: [REDACTED])';
}

class AuthSignOutRequested extends AuthEvent {}

// Event for updating password from UpdatePasswordPage
class AuthPasswordUpdateRequested extends AuthEvent {
  final String newPassword;

  const AuthPasswordUpdateRequested({required this.newPassword});

  @override
  List<Object> get props => [newPassword];

  @override
  String toString() => 'AuthPasswordUpdateRequested(newPassword: [REDACTED])';
}

// Internal event now carries UserEntity?
class _AuthUserChanged extends AuthEvent {
  final UserEntity? user; // Changed from Supabase User?
  const _AuthUserChanged(this.user);

  @override
  List<Object?> get props => [user];

  @override
  String toString() => '_AuthUserChanged(user: [REDACTED])';
}
