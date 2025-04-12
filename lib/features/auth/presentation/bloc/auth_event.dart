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
}

class AuthSignUpRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthSignUpRequested({required this.email, required this.password});

  @override
  List<Object> get props => [email, password];
}

class AuthRecoverPasswordRequested extends AuthEvent {
  final String email;
  const AuthRecoverPasswordRequested(this.email);

  @override
  List<Object> get props => [email];
}

class AuthSignOutRequested extends AuthEvent {}

// Internal event now carries UserEntity?
class _AuthUserChanged extends AuthEvent {
  final UserEntity? user; // Changed from Supabase User?
  const _AuthUserChanged(this.user);

  @override
  List<Object?> get props => [user];
}