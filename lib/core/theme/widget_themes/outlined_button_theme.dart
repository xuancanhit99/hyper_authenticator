import 'package:flutter/material.dart';

import 'package:hyper_authenticator/core/constants/app_colors.dart';

class COutlinedButtonTheme {
  COutlinedButtonTheme._();

  static final lightOutlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      foregroundColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.primaryLight),
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  );
  static final darkOutlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      foregroundColor: AppColors.primaryDark,
      side: const BorderSide(color: AppColors.primaryDark),
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  );
}
