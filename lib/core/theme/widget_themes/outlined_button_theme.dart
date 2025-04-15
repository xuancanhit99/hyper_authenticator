import 'package:flutter/material.dart';

import 'package:hyper_authenticator/core/constants/app_colors.dart';

class COutlinedButtonTheme {
  COutlinedButtonTheme._();
  
  static final lightOutlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)
        ),
        foregroundColor: AppColors.cSecondaryColor,
        side: const BorderSide(color: AppColors.cSecondaryColor),
        padding: const EdgeInsets.symmetric(vertical: 15)
    ),
  );
  static final darkOutlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)
        ),
        foregroundColor: AppColors.cWhiteColor,
        side: const BorderSide(color: AppColors.cWhiteColor),
        padding: const EdgeInsets.symmetric(vertical: 15)
    ),
  );

}