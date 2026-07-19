import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void expectPrimaryFocusWithin(Finder finder) {
  final primaryFocus = FocusManager.instance.primaryFocus;
  expect(primaryFocus, isNotNull, reason: 'Không có primary focus.');

  final focusedContext = primaryFocus!.context;
  expect(
    focusedContext,
    isNotNull,
    reason: 'Focus node không có BuildContext.',
  );

  final targets = finder.evaluate().toSet();
  var matches = targets.contains(focusedContext);
  focusedContext!.visitAncestorElements((ancestor) {
    if (targets.contains(ancestor)) {
      matches = true;
      return false;
    }
    return true;
  });

  expect(
    matches,
    isTrue,
    reason:
        'Primary focus `${focusedContext.widget.runtimeType}` '
        'không nằm trong `${finder.describeMatch(Plurality.one)}`.',
  );
}

Future<void> pressTab(WidgetTester tester, {bool reverse = false}) async {
  if (reverse) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.pump();
}
