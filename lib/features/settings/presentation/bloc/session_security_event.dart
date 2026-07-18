part of 'session_security_bloc.dart';

sealed class SessionSecurityEvent extends Equatable {
  const SessionSecurityEvent();

  @override
  List<Object> get props => const [];
}

final class RevokeOtherSessionsRequested extends SessionSecurityEvent {
  const RevokeOtherSessionsRequested();
}
