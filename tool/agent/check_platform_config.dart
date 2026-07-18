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
    'windows/runner/Runner.rc',
    'VALUE "ProductName", "Hyper Authenticator"',
    'Windows product metadata',
  );
  requireText(
    'windows/CMakeLists.txt',
    '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS',
    'MSVC 14.51 compatibility cho local_auth_windows 2.0.1',
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
