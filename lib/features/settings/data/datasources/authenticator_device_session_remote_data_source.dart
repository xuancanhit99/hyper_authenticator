import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/settings/data/datasources/authenticator_installation_identity_store.dart';
import 'package:hyper_authenticator/features/settings/data/models/remote_authenticator_device_session.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

@lazySingleton
class AuthenticatorDeviceSessionRemoteDataSource {
  static const registerFunctionName = 'register_current_authenticator_device';
  static const listFunctionName = 'list_authenticator_device_sessions';
  static const revokeFunctionName = 'revoke_authenticator_device_session';

  final SupabaseClient _client;

  AuthenticatorDeviceSessionRemoteDataSource(this._client);

  Future<List<RemoteAuthenticatorDeviceSession>> registerAndList({
    required String userId,
    required AuthenticatorInstallationIdentity identity,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final registration = await _client.rpc(
        registerFunctionName,
        params: <String, dynamic>{
          'p_installation_id': identity.installationId,
          'p_display_name': identity.displayName,
          'p_platform': identity.platform,
        },
      );
      if (registration is! List ||
          registration.length != 1 ||
          registration.single is! Map ||
          (registration.single as Map)['registration_id'] is! String ||
          !Uuid.isValidUUID(
            fromString:
                (registration.single as Map)['registration_id'] as String,
          )) {
        throw const FormatException('Device registration response lỗi.');
      }

      _requireAuthenticatedUser(userId);
      final response = await _client.rpc(listFunctionName);
      if (response is! List) {
        throw const FormatException('Device session list response lỗi.');
      }
      final devices = response
          .map((row) {
            if (row is! Map) {
              throw const FormatException('Device session row lỗi.');
            }
            return RemoteAuthenticatorDeviceSession.fromRow(
              Map<String, dynamic>.from(row),
            );
          })
          .toList(growable: false);
      if (devices.where((device) => device.isCurrent).length != 1) {
        throw const FormatException(
          'Device session list thiếu current session duy nhất.',
        );
      }
      return devices;
    } on PostgrestException catch (error) {
      if (error.message.contains('session_revoked')) {
        throw const AuthServerException(
          'Phiên đăng nhập hiện tại đã bị thu hồi.',
        );
      }
      throw const ServerException(
        'Không thể tải danh sách thiết bị đã đăng nhập.',
      );
    } on FormatException {
      throw const ServerException('Device registry trả dữ liệu không hợp lệ.');
    }
  }

  Future<void> revoke({
    required String userId,
    required String registrationId,
  }) async {
    _requireAuthenticatedUser(userId);
    try {
      final response = await _client.rpc(
        revokeFunctionName,
        params: <String, dynamic>{'p_registration_id': registrationId},
      );
      if (response != true) {
        throw const FormatException('Device revoke response lỗi.');
      }
    } on PostgrestException catch (error) {
      if (error.message.contains('cannot_revoke_current_device_session')) {
        throw const ServerException(
          'Không thể thu hồi thiết bị đang dùng; hãy dùng Đăng xuất.',
        );
      }
      if (error.code == 'PT404' ||
          error.message.contains('device_session_not_found')) {
        throw const ServerException(
          'Phiên thiết bị không còn hoạt động; hãy tải lại danh sách.',
        );
      }
      if (error.message.contains('session_revoked')) {
        throw const AuthServerException(
          'Phiên đăng nhập hiện tại đã bị thu hồi.',
        );
      }
      throw const ServerException(
        'Không xác định được trạng thái thu hồi; hãy tải lại danh sách trước khi thử lại.',
      );
    } on FormatException {
      throw const ServerException(
        'Server không xác nhận đã thu hồi phiên thiết bị.',
      );
    }
  }

  void _requireAuthenticatedUser(String expectedUserId) {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      throw const AuthException('User not logged in');
    }
    if (currentUser.id != expectedUserId) {
      throw const AuthException('Authenticated user changed during operation');
    }
  }
}
