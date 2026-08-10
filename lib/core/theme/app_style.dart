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
    AppStyle.securityMinimal => 'Mặc định',
    AppStyle.oledDark => 'OLED',
    AppStyle.darkCinema => 'Indigo',
  };

  String get description => switch (this) {
    AppStyle.securityMinimal => 'Xanh lá, rõ ràng và tương phản cao',
    AppStyle.oledDark => 'Nền đen tuyền khi dùng chế độ tối',
    AppStyle.darkCinema => 'Tông chàm với bề mặt bo góc mềm',
  };
}
