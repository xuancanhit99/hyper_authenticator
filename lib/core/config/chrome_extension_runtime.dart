/// Compile-time switch used only by the dedicated Chrome Extension entrypoint.
///
/// A normal Flutter Web deployment leaves this false. The distinction matters
/// because an MV3 extension has a different storage and executable-code
/// boundary from a website, even though both run on the web platform.
abstract final class ChromeExtensionRuntime {
  static const bool isEnabled = bool.fromEnvironment('HYPER_CHROME_EXTENSION');
}
