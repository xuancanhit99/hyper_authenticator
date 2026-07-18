part of 'session_security_bloc.dart';

sealed class SessionSecurityState extends Equatable {
  const SessionSecurityState();

  @override
  List<Object> get props => const [];
}

final class SessionSecurityIdle extends SessionSecurityState {
  const SessionSecurityIdle();
}

final class SessionSecurityInProgress extends SessionSecurityState {
  const SessionSecurityInProgress();
}

final class SessionSecuritySuccess extends SessionSecurityState {
  const SessionSecuritySuccess();
}

final class SessionSecurityFailure extends SessionSecurityState {
  final String message;

  const SessionSecurityFailure(this.message);

  @override
  List<Object> get props => [message];
}
