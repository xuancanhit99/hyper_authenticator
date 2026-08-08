import 'package:flutter/foundation.dart';
import 'package:hyper_authenticator/core/config/chrome_extension_runtime.dart';

abstract final class PlatformCapabilities {
  static bool get supportsLocalAuthentication {
    if (kIsWeb) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.fuchsia || TargetPlatform.linux => false,
    };
  }

  static bool get supportsBarcodeScanning {
    if (ChromeExtensionRuntime.isEnabled) {
      return false;
    }
    if (kIsWeb) {
      return true;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => false,
    };
  }

  static bool get supportsBarcodeImageAnalysis {
    if (ChromeExtensionRuntime.isEnabled) {
      return false;
    }
    if (kIsWeb) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      TargetPlatform.fuchsia ||
      TargetPlatform.linux ||
      TargetPlatform.windows => false,
    };
  }

  /// Chrome Extension MVP intentionally excludes protected QR export because
  /// browser extension storage has no equivalent to a fresh OS-auth prompt.
  static bool get supportsProtectedExport =>
      !ChromeExtensionRuntime.isEnabled && supportsLocalAuthentication;
}
