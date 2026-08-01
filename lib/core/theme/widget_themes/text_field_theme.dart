import 'package:flutter/material.dart';

class CTextFormFieldTheme {
  CTextFormFieldTheme._();

  static InputDecorationTheme themed({required Color primary}) {
    return InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(100)),
      prefixIconColor: primary,
      floatingLabelStyle: TextStyle(color: primary),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(100),
        borderSide: BorderSide(width: 2, color: primary),
      ),
    );
  }
}
