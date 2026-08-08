import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';

void main() {
  test('light/dark dùng cùng page transition native theo platform', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final builders = theme.pageTransitionsTheme.builders;
      expect(
        builders[TargetPlatform.android],
        isA<PredictiveBackPageTransitionsBuilder>(),
      );
      expect(
        builders[TargetPlatform.iOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      expect(
        builders[TargetPlatform.macOS],
        isA<CupertinoPageTransitionsBuilder>(),
      );
      expect(
        builders[TargetPlatform.windows],
        isA<ZoomPageTransitionsBuilder>(),
      );
      expect(builders[TargetPlatform.linux], isA<ZoomPageTransitionsBuilder>());
    }
  });
}
