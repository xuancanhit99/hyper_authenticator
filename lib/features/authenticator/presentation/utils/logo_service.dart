import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart'; // For Image asset check

class LogoService {
  static const String _jsonPath = 'assets/data/authenticator_logo_map.json';
  static const String _logoBasePath = 'assets/logos/authenticators/';
  static const String _defaultLogoPath =
      '${_logoBasePath}default.png'; // Assume you have a default.png

  Map<String, String>? _logoMap;
  bool _isLoaded = false;

  // Private constructor for singleton pattern
  LogoService._privateConstructor();
  static final LogoService _instance = LogoService._privateConstructor();

  // Static instance getter
  static LogoService get instance => _instance;

  Future<void> loadLogoMap() async {
    if (_isLoaded) return; // Already loaded

    try {
      final String jsonString = await rootBundle.loadString(_jsonPath);
      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      // Ensure values are strings
      _logoMap = jsonMap.map((key, value) => MapEntry(key, value.toString()));
      _isLoaded = true;
      print('Authenticator logo map loaded successfully.');
    } catch (e) {
      print('Error loading authenticator logo map: $e');
      _logoMap = {}; // Assign empty map on error to prevent null issues
      _isLoaded = true; // Mark as loaded even if error occurred
    }
  }

  String getLogoPath(String? issuer) {
    if (!_isLoaded || _logoMap == null || issuer == null || issuer.isEmpty) {
      // Consider logging this state if it's unexpected
      return _defaultLogoPath;
    }

    final String lowerCaseIssuer = issuer.toLowerCase().trim();
    final String? logoName = _logoMap![lowerCaseIssuer];

    if (logoName != null && logoName.isNotEmpty) {
      final String potentialPath = '$_logoBasePath$logoName.png';
      // Optional: Check if the asset actually exists before returning?
      // This adds overhead but prevents broken images if map is out of sync.
      // For simplicity, we'll assume the map is correct for now.
      // If you add asset checking, make it asynchronous or handle errors gracefully.
      return potentialPath;
    }

    // Fallback for common variations or generic terms if needed
    // e.g., if (_logoMap!.containsKey(lowerCaseIssuer.split(' ').first)) { ... }

    return _defaultLogoPath;
  }

  // Optional: Helper to preload the default image to avoid flicker
  // Future<void> preloadDefaultLogo(BuildContext context) async {
  //   await precacheImage(AssetImage(_defaultLogoPath), context);
  // }
}
