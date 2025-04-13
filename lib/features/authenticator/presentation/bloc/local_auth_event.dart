part of 'local_auth_bloc.dart';

abstract class LocalAuthEvent extends Equatable {
  const LocalAuthEvent();

  @override
  List<Object> get props => [];
}

/// Event to check if authentication is supported and required.
class CheckLocalAuth extends LocalAuthEvent {}

/// Event to trigger the local authentication prompt (Biometric/PIN).
class Authenticate extends LocalAuthEvent {}
