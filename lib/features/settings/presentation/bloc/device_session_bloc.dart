import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/features/settings/domain/entities/authenticator_device_session.dart';
import 'package:hyper_authenticator/features/settings/domain/repositories/authenticator_device_session_repository.dart';
import 'package:injectable/injectable.dart';

part 'device_session_event.dart';
part 'device_session_state.dart';

@injectable
class DeviceSessionBloc extends Bloc<DeviceSessionEvent, DeviceSessionState> {
  final AuthenticatorDeviceSessionRepository _repository;
  bool _operationInProgress = false;
  String? _latestLoadUserId;

  DeviceSessionBloc(this._repository) : super(const DeviceSessionInitial()) {
    on<LoadDeviceSessionsRequested>(_onLoadRequested);
    on<RevokeDeviceSessionRequested>(_onRevokeRequested);
  }

  Future<void> _onLoadRequested(
    LoadDeviceSessionsRequested event,
    Emitter<DeviceSessionState> emit,
  ) async {
    _latestLoadUserId = event.userId;
    if (_operationInProgress) return;
    _operationInProgress = true;
    emit(DeviceSessionLoading(event.userId));
    try {
      final result = await _repository.load(userId: event.userId);
      if (_latestLoadUserId == event.userId) {
        result.fold(
          (failure) =>
              emit(DeviceSessionLoadFailure(event.userId, failure.message)),
          (devices) => emit(DeviceSessionsLoaded(event.userId, devices)),
        );
      }
    } finally {
      _operationInProgress = false;
      _schedulePendingLoad(event.userId);
    }
  }

  Future<void> _onRevokeRequested(
    RevokeDeviceSessionRequested event,
    Emitter<DeviceSessionState> emit,
  ) async {
    if (_operationInProgress) return;
    if (state.userId != event.userId) {
      emit(
        DeviceSessionLoadFailure(
          event.userId,
          'Danh sách thiết bị không thuộc phiên hiện tại; hãy tải lại.',
        ),
      );
      return;
    }
    final previous = state.devices;
    final target = previous
        .where((device) => device.registrationId == event.registrationId)
        .firstOrNull;
    if (target == null) {
      emit(
        DeviceSessionActionFailure(
          event.userId,
          previous,
          'Phiên thiết bị không còn trong danh sách; hãy tải lại.',
        ),
      );
      return;
    }
    if (target.isCurrent) {
      emit(
        DeviceSessionActionFailure(
          event.userId,
          previous,
          'Không thể thu hồi thiết bị đang dùng; hãy dùng Đăng xuất.',
        ),
      );
      return;
    }

    _operationInProgress = true;
    emit(DeviceSessionRevoking(event.userId, previous, target.registrationId));
    try {
      final result = await _repository.revoke(
        userId: event.userId,
        registrationId: target.registrationId,
      );
      if (_latestLoadUserId == event.userId) {
        result.fold(
          (failure) => emit(
            DeviceSessionActionFailure(event.userId, previous, failure.message),
          ),
          (_) => emit(
            DeviceSessionRevocationSuccess(
              event.userId,
              previous
                  .where(
                    (device) => device.registrationId != target.registrationId,
                  )
                  .toList(growable: false),
              target.displayName,
            ),
          ),
        );
      }
    } finally {
      _operationInProgress = false;
      _schedulePendingLoad(event.userId);
    }
  }

  void _schedulePendingLoad(String completedUserId) {
    final pendingUserId = _latestLoadUserId;
    if (!isClosed &&
        pendingUserId != null &&
        pendingUserId != completedUserId) {
      add(LoadDeviceSessionsRequested(pendingUserId));
    }
  }
}
