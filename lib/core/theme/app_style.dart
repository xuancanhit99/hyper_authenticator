/// Visual style (skin) of the app, orthogonal to [ThemeMode].
///
/// Each style ships a full light + dark palette so the user can combine any
/// style with any brightness mode. Persisted by name — keep enum names stable.
enum AppStyle {
  /// Brand-green Material 3, flat and high-contrast. Default.
  securityMinimal,

  /// OLED-oriented style; its dark variant is pure black with accent OTP codes.
  oledDark,

  /// Indigo-accented surfaces with larger radii; dark is the layered variant.
  darkCinema;

  static AppStyle fromName(String? name) {
    return AppStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => AppStyle.securityMinimal,
    );
  }

  String get label => switch (this) {
    AppStyle.securityMinimal => 'Security Minimal',
    AppStyle.oledDark => 'OLED Dark',
    AppStyle.darkCinema => 'Dark Cinema',
  };

  String get description => switch (this) {
    AppStyle.securityMinimal => 'Xanh lá brand, phẳng, tương phản cao',
    AppStyle.oledDark => 'Dark đen tuyền, OTP accent; Light nền trắng',
    AppStyle.darkCinema => 'Tối cao cấp, accent indigo, bo góc lớn',
  };
}
