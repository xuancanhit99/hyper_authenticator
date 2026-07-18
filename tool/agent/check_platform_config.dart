import 'dart:io';

void main() {
  final root = Directory.current.absolute;
  final failures = <String>[];

  void requireText(String path, String expected, String reason) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) {
      failures.add('Thiếu $path ($reason)');
      return;
    }
    if (!file.readAsStringSync().contains(expected)) {
      failures.add('$path thiếu $reason');
    }
  }

  requireText(
    'android/app/src/main/AndroidManifest.xml',
    'android.permission.INTERNET',
    'INTERNET permission cho release Auth/Sync',
  );
  requireText(
    'android/app/src/main/AndroidManifest.xml',
    'android:allowBackup="false"',
    'backup policy bảo vệ local vault',
  );
  requireText(
    'android/app/src/main/AndroidManifest.xml',
    'android:usesCleartextTraffic="false"',
    'cleartext network fail-closed',
  );
  requireText(
    'android/app/build.gradle.kts',
    'throw GradleException(',
    'release signing fail-closed',
  );
  requireText(
    'android/app/build.gradle.kts',
    'applicationId = "app.hyperz.authenticator"',
    'production application ID',
  );

  for (final path in [
    'ios/Runner/DebugProfile.entitlements',
    'ios/Runner/Release.entitlements',
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    requireText(path, '<key>keychain-access-groups</key>', 'Keychain Sharing');
  }
  for (final key in [
    'NSCameraUsageDescription',
    'NSFaceIDUsageDescription',
    'NSPhotoLibraryUsageDescription',
  ]) {
    requireText(
      'ios/Runner/Info.plist',
      '<key>$key</key>',
      '$key privacy text',
    );
    requireText(
      'macos/Runner/Info.plist',
      '<key>$key</key>',
      '$key privacy text',
    );
  }
  for (final path in [
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    requireText(
      path,
      '<key>com.apple.security.app-sandbox</key>',
      'App Sandbox entitlement',
    );
    requireText(
      path,
      '<key>com.apple.security.network.client</key>',
      'outbound network entitlement',
    );
    requireText(
      path,
      '<key>com.apple.security.device.camera</key>',
      'camera entitlement',
    );
  }

  requireText(
    'macos/Runner/Configs/AppInfo.xcconfig',
    'PRODUCT_BUNDLE_IDENTIFIER = app.hyperz.authenticator',
    'production bundle ID',
  );
  requireText(
    'linux/CMakeLists.txt',
    'set(APPLICATION_ID "app.hyperz.authenticator")',
    'production application ID',
  );
  requireText(
    '.github/workflows/ci.yml',
    'scripts/agent/linux_integration.sh',
    'Linux isolated local-vault runtime gate',
  );
  requireText(
    '.github/workflows/ci.yml',
    'scripts/agent/linux_package_smoke.sh',
    'Linux package install/upgrade/remove gate',
  );
  requireText(
    '.github/workflows/ci.yml',
    r'hyper-authenticator-linux-deb-${{ github.sha }}',
    'Linux immutable Debian artifact',
  );
  requireText(
    'scripts/agent/linux_integration.sh',
    r'XDG_DATA_HOME="$SANDBOX/data"',
    'Linux integration storage sandbox',
  );
  requireText(
    'scripts/agent/linux_integration.sh',
    r'${CI:-} != true',
    'Linux integration CI-only guard',
  );
  requireText(
    'scripts/agent/linux_e2ee_integration.sh',
    'service-role key không được đi vào client integration harness',
    'Linux E2EE service-role boundary',
  );
  requireText(
    'scripts/agent/linux_e2ee_integration.sh',
    'integration_test/encrypted_sync_smoke_test.dart',
    'Linux authenticated E2EE runtime gate',
  );
  requireText(
    'scripts/agent/linux_e2ee_container.sh',
    'git ls-files --cached --others --exclude-standard -z',
    'Linux E2EE container source allowlist',
  );
  requireText(
    'scripts/agent/linux_e2ee_operator.sh',
    'remote-cleanup-verified',
    'isolated E2EE user cleanup verification',
  );
  requireText(
    'integration_test/encrypted_sync_smoke_test.dart',
    'ALLOW_E2EE_REMOTE_TEST_MUTATION',
    'explicit remote mutation opt-in',
  );
  requireText(
    'windows/runner/Runner.rc',
    'VALUE "ProductName", "Hyper Authenticator"',
    'Windows product metadata',
  );
  requireText(
    'windows/CMakeLists.txt',
    '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS',
    'MSVC 14.51 compatibility cho local_auth_windows 2.0.1',
  );
  requireText(
    'lib/core/router/app_url_strategy_web.dart',
    'usePathUrlStrategy();',
    'Web path URL strategy cho reverse-proxy deep link',
  );
  requireText(
    'lib/main.dart',
    'configureAppUrlStrategy();',
    'bootstrap Web path URL strategy',
  );

  final platformFiles = <String>[
    'android/app/build.gradle.kts',
    'ios/Runner.xcodeproj/project.pbxproj',
    'macos/Runner/Configs/AppInfo.xcconfig',
    'linux/CMakeLists.txt',
    'windows/runner/Runner.rc',
  ];
  for (final path in platformFiles) {
    final content = File('${root.path}/$path').readAsStringSync();
    if (content.contains('com.example')) {
      failures.add('$path còn identifier com.example');
    }
  }

  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('LỖI $failure');
    }
    stderr.writeln(
      'Platform configuration gate thất bại với ${failures.length} vấn đề.',
    );
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Platform configuration gate pass: network, backup, signing, Keychain và IDs.',
  );
}
