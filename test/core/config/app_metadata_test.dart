import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/config/app_metadata.dart';

void main() {
  test('metadata hiển thị khớp version canonical trong pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([^+\s]+)\+([^\s]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(AppMetadata.versionName, match!.group(1));
    expect(AppMetadata.buildNumber, match.group(2));
    expect(
      AppMetadata.versionLabel,
      'Phiên bản ${match.group(1)} (${match.group(2)})',
    );

    final extensionManifest =
        jsonDecode(File('chrome_extension/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(extensionManifest['version'], match.group(1));
  });
}
