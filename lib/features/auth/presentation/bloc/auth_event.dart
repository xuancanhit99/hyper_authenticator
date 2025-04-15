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
  final bool rememberMe; // Added rememberMe flag

  const AuthSignInRequested({
    required this.email,
    required this.password,
    required this.rememberMe, // Added rememberMe flag
  });

  @override
  List<Object> get props => [email, password, rememberMe]; // Added rememberMe flag
}

class AuthSignUpRequested extends AuthEvent {
  final String name; // Added
  final String email;
  final String password;
  // final String? phone; // REMOVED

  const AuthSignUpRequested({
    required this.name,
    required this.email,
    required this.password,
    // this.phone, // REMOVED
  });

  @override
  List<Object?> get props => [name, email, password]; // REMOVED phone from props
}

class AuthRecoverPasswordRequested extends AuthEvent {
  final String email;
  const AuthRecoverPasswordRequested(this.email);

  @override
  List<Object> get props => [email];
}

/// Event to load the remembered email from SharedPreferences.
class LoadRememberedUser extends AuthEvent {}

class AuthSignOutRequested extends AuthEvent {}

// Event for updating password from UpdatePasswordPage
class AuthPasswordUpdateRequested extends AuthEvent {
  final String newPassword;

  const AuthPasswordUpdateRequested({required this.newPassword});

  @override
  List<Object> get props => [newPassword];
}

// Internal event now carries UserEntity?
class _AuthUserChanged extends AuthEvent {
  final UserEntity? user; // Changed from Supabase User?
  const _AuthUserChanged(this.user);

  @override
  List<Object?> get props => [user];
}
