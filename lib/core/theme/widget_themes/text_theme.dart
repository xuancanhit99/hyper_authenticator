import 'package:flutter/material.dart';

class CTextTheme {
  // static TextTheme lightTextTheme = TextTheme(bodyLarge: GoogleFonts.poppins(color: Colors.black, fontSize: 24));
  static TextTheme lightTextTheme = const TextTheme(
    headlineSmall: TextStyle(fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontWeight: FontWeight.bold),
    headlineLarge: TextStyle(fontWeight: FontWeight.bold),
  );
  static TextTheme darkTextTheme = const TextTheme(
    headlineSmall: TextStyle(fontWeight: FontWeight.bold),
    headlineMedium: TextStyle(fontWeight: FontWeight.bold),
    headlineLarge: TextStyle(fontWeight: FontWeight.bold),
    // labelLarge:
    //     TextStyle(fontFamily: 'Averta', color: Colors.black),
  );
}
