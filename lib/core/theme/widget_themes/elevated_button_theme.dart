import 'package:flutter/material.dart';

import 'package:hyper_authenticator/core/constants/app_colors.dart';

class CElevatedButtonTheme {
  CElevatedButtonTheme._();

  static final lightElevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      foregroundColor: AppColors.cWhiteColor,
      backgroundColor: AppColors.primaryLight,
      side: const BorderSide(color: AppColors.primaryLight),
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  );
  static final darkElevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      foregroundColor: AppColors.onPrimaryDark,
      backgroundColor: AppColors.primaryDark,
      side: const BorderSide(color: AppColors.primaryDark),
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  );
}
