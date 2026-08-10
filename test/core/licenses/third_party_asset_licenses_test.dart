import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/licenses/third_party_asset_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Sentinel Icons MIT License được đăng ký cho LicensePage', () async {
    registerThirdPartyAssetLicenses();

    final entry = await LicenseRegistry.licenses.firstWhere(
      (candidate) => candidate.packages.contains('sentinel-icons'),
    );
    final text = entry.paragraphs.map((paragraph) => paragraph.text).join('\n');

    expect(text, contains('MIT License'));
    expect(text, contains('Copyright (c) 2022 tommycarpi'));
  });
}
