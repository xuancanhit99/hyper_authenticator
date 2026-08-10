import 'package:flutter/material.dart';

class CTextFormFieldTheme {
  CTextFormFieldTheme._();

  static InputDecorationTheme themed({
    required Color primary,
    double radius = 20,
  }) {
    final borderRadius = BorderRadius.circular(radius);
    return InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: borderRadius),
      prefixIconColor: primary,
      floatingLabelStyle: TextStyle(color: primary),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(width: 2, color: primary),
      ),
    );
  }
}
