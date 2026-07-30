import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/constants/app_colors.dart';

class CTextFormFieldTheme {
  CTextFormFieldTheme._();

  static InputDecorationTheme lightInputDecorationTheme = InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(100)),
    prefixIconColor: AppColors.primaryLight,
    floatingLabelStyle: const TextStyle(color: AppColors.primaryLight),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(100),
      borderSide: const BorderSide(width: 2, color: AppColors.primaryLight),
    ),
  );

  static InputDecorationTheme darkInputDecorationTheme = InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(100)),
    prefixIconColor: AppColors.primaryDark,
    floatingLabelStyle: const TextStyle(color: AppColors.primaryDark),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(100),
      borderSide: const BorderSide(width: 2, color: AppColors.primaryDark),
    ),
  );
}
