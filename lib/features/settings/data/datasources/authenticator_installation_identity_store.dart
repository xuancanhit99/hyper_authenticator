import 'package:flutter/foundation.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthenticatorInstallationIdentity {
  final String installationId;
  final String displayName;
  final String platform;

  const AuthenticatorInstallationIdentity({
    required this.installationId,
    required this.displayName,
    required this.platform,
  });
}

@lazySingleton
class AuthenticatorInstallationIdentityStore {
  static const preferenceKey = 'authenticator_installation_id_v1';

  final SharedPreferences _preferences;
  final Uuid _uuid;

  AuthenticatorInstallationIdentityStore(this._preferences, this._uuid);

  Future<AuthenticatorInstallationIdentity> readOrCreate() async {
    var installationId = _preferences.getString(preferenceKey);
    if (installationId == null || !_isUuidV4(installationId)) {
      installationId = _uuid.v4();
      final persisted = await _preferences.setString(
        preferenceKey,
        installationId,
      );
      if (!persisted) {
        throw const CacheException(
          'Không thể lưu định danh cài đặt cho device registry.',
        );
      }
    }

    final platform = _platformCode;
    return AuthenticatorInstallationIdentity(
      installationId: installationId,
      displayName: 'Hyper Authenticator trên ${_platformLabel(platform)}',
      platform: platform,
    );
  }

  bool _isUuidV4(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  String get _platformCode {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'unknown',
    };
  }

  String _platformLabel(String platform) => switch (platform) {
    'android' => 'Android',
    'ios' => 'iOS',
    'macos' => 'macOS',
    'windows' => 'Windows',
    'linux' => 'Linux',
    'web' => 'Web',
    _ => 'thiết bị này',
  };
}
