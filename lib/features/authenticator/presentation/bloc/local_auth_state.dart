part of 'local_auth_bloc.dart';

abstract class LocalAuthState extends Equatable {
  const LocalAuthState();

  @override
  List<Object> get props => [];
}

/// Initial state, authentication status unknown.
class LocalAuthInitial extends LocalAuthState {}

/// State indicating local authentication is required and not yet passed.
class LocalAuthRequired extends LocalAuthState {}

/// State indicating local authentication has been successfully passed.
class LocalAuthSuccess extends LocalAuthState {}

/// State indicating local authentication is not available or not configured on the device.
class LocalAuthUnavailable extends LocalAuthState {}

/// State when an error occurs during local authentication.
class LocalAuthError extends LocalAuthState {
  final String message;

  const LocalAuthError(this.message);

  @override
  List<Object> get props => [message];
}
