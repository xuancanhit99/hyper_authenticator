import 'package:flutter/material.dart';
import 'package:hyper_authenticator/core/constants/app_colors.dart';

class CTextFormFieldTheme {
  CTextFormFieldTheme._();

  static InputDecorationTheme lightInputDecorationTheme = InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(100)),
      prefixIconColor: AppColors.cSecondaryColor,
      floatingLabelStyle: const TextStyle(color: AppColors.cSecondaryColor),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(100),
        borderSide: const BorderSide(width: 2, color: AppColors.cSecondaryColor),
      ));

  static InputDecorationTheme darkInputDecorationTheme = InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(100)),
      prefixIconColor: AppColors.cPrimaryColor,
      floatingLabelStyle: const TextStyle(color: AppColors.cPrimaryColor),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(100),
        borderSide: const BorderSide(width: 2, color: AppColors.cPrimaryColor),
      ));
}
