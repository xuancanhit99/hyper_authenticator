import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _sentinelIconsLicensePath = 'third_party/sentinel-icons/LICENSE';

bool _thirdPartyAssetLicensesRegistered = false;

/// Đưa license của asset vendored vào LicensePage chuẩn của Flutter.
void registerThirdPartyAssetLicenses() {
  if (_thirdPartyAssetLicensesRegistered) return;
  _thirdPartyAssetLicensesRegistered = true;

  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString(_sentinelIconsLicensePath);
    yield LicenseEntryWithLineBreaks(const ['sentinel-icons'], license);
  });
}
