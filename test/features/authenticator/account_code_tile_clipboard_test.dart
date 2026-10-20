import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_code_tile.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/circular_countdown_timer.dart';

const _successMessage = 'Đã sao chép mã TOTP.';
const _failureMessage = 'Không thể sao chép mã TOTP. Hãy thử lại.';
const _testAccount = AuthenticatorAccount(
  id: 'clipboard-test-account',
  issuer: 'TEST_ONLY Clipboard',
  accountName: 'clipboard@example.invalid',
  secretKey: 'TEST_ONLY_UNUSED_SECRET',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Completer<void> write;
  late List<MethodCall> writes;

  setUp(() {
    writes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            writes.add(call);
            await write.future;
          }
          return null;
        });
  });

  tearDown(() {
    if (!write.isCompleted) write.complete();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('không báo sao chép thành công khi clipboard còn pending', (
    tester,
  ) async {
    write = Completer<void>();
    await tester.pumpWidget(_buildApp());

    await tester.tap(find.text('123 456'));
    await tester.pump();

    expect(writes, hasLength(1));
    expect(writes.single.arguments, {'text': '123456'});
    expect(find.text(_successMessage), findsNothing);
    expect(find.text(_failureMessage), findsNothing);

    write.complete();
    await tester.pump();
  });

  testWidgets('chỉ báo thành công sau khi clipboard xác nhận write', (
    tester,
  ) async {
    write = Completer<void>();
    await tester.pumpWidget(_buildApp());
    await tester.tap(find.text('123 456'));
    await tester.pump();

    write.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(_successMessage), findsOneWidget);
    expect(find.text(_failureMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clipboard PlatformException chỉ hiển thị lỗi cố định', (
    tester,
  ) async {
    write = Completer<void>();
    await tester.pumpWidget(_buildApp());
    await tester.tap(find.text('123 456'));
    await tester.pump();

    write.completeError(
      PlatformException(
        code: 'clipboard_denied',
        message: 'TEST_ONLY_PRIVATE_PLATFORM_ERROR',
        details: 'TEST_ONLY_PRIVATE_PLATFORM_DETAILS',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text(_successMessage), findsNothing);
    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.textContaining('TEST_ONLY_PRIVATE_PLATFORM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final fails in [false, true]) {
    testWidgets(
      'clipboard ${fails ? 'failure' : 'success'} sau unmount không hiện feedback hoặc lỗi',
      (tester) async {
        write = Completer<void>();
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        await tester.pumpWidget(_buildApp(visible: visible));
        await tester.tap(find.text('123 456'));
        await tester.pump();
        expect(writes, hasLength(1));

        visible.value = false;
        await tester.pump();
        expect(find.byType(AccountCodeTile), findsNothing);

        if (fails) {
          write.completeError(
            PlatformException(code: 'TEST_ONLY_UNMOUNTED_CLIPBOARD_FAILURE'),
          );
        } else {
          write.complete();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.text(_successMessage), findsNothing);
        expect(find.text(_failureMessage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _buildApp({ValueNotifier<bool>? visible}) => MaterialApp(
  home: Scaffold(
    body: visible == null
        ? _buildTile()
        : ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, showTile, _) =>
                showTile ? _buildTile() : const SizedBox.shrink(),
          ),
  ),
);

Widget _buildTile() => AccountCodeTile(
  account: _testAccount,
  displayCode: '123 456',
  timeWindow: const TotpTimeWindow(timeStep: 1, secondsRemaining: 20),
  onEdit: () {},
  onDelete: () {},
);
