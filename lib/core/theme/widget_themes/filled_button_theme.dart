import 'package:flutter/material.dart';

/// Shared primary-action geometry for Material 3 [FilledButton] controls.
///
/// Colors deliberately come from the active [ColorScheme] so a destructive
/// action can override its background without inheriting a mismatched brand
/// foreground color.
class CFilledButtonTheme {
  CFilledButtonTheme._();

  static final filledButtonTheme = FilledButtonThemeData(
    style: FilledButton.styleFrom(
      elevation: 0,
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
