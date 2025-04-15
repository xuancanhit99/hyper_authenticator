import 'package:flutter/material.dart';

import 'package:hyper_authenticator/core/constants/app_colors.dart';

class CElevatedButtonTheme {
  CElevatedButtonTheme._();

  static final lightElevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)
        ),
        foregroundColor: AppColors.cWhiteColor,
        backgroundColor: AppColors.cSecondaryColor,
        side: const BorderSide(color: AppColors.cSecondaryColor),
        padding: const EdgeInsets.symmetric(vertical: 15)
    ),
  );
  static final darkElevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)
        ),
        foregroundColor: AppColors.cSecondaryColor,
        backgroundColor: AppColors.cWhiteColor,
        side: const BorderSide(color: AppColors.cWhiteColor),
        padding: const EdgeInsets.symmetric(vertical: 15)
    ),
  );

}