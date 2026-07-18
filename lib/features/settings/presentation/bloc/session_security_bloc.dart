import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:injectable/injectable.dart';

part 'session_security_event.dart';
part 'session_security_state.dart';

@injectable
class SessionSecurityBloc
    extends Bloc<SessionSecurityEvent, SessionSecurityState> {
  final AuthRepository _authRepository;
  bool _isRevoking = false;

  SessionSecurityBloc(this._authRepository)
    : super(const SessionSecurityIdle()) {
    on<RevokeOtherSessionsRequested>(_onRevokeOtherSessionsRequested);
  }

  Future<void> _onRevokeOtherSessionsRequested(
    RevokeOtherSessionsRequested event,
    Emitter<SessionSecurityState> emit,
  ) async {
    if (_isRevoking) {
      return;
    }
    _isRevoking = true;
    emit(const SessionSecurityInProgress());
    try {
      final result = await _authRepository.revokeOtherSessions();
      result.fold(
        (failure) => emit(SessionSecurityFailure(failure.message)),
        (_) => emit(const SessionSecuritySuccess()),
      );
    } finally {
      _isRevoking = false;
    }
  }
}
