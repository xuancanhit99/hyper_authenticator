import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/services/provider_logo_catalog.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/widgets/account_avatar.dart';

void main() {
  ProviderLogoCatalog catalog({
    Map<String, String> mapping = const {},
    Iterable<String> assetPaths = const {
      'assets/logos/authenticators/google.png',
    },
  }) => ProviderLogoCatalog.fromData(mapping: mapping, assetPaths: assetPaths);

  Widget app(Widget child) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.green),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('provider đã nhận diện render asset trong clip tròn', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AccountAvatar(
          issuer: 'Google',
          logoCatalog: catalog(mapping: const {'google': 'google'}),
        ),
      ),
    );

    final imageFinder = find.byKey(const Key('provider-logo-google'));
    expect(imageFinder, findsOneWidget);
    expect(find.byType(ClipOval), findsOneWidget);
    final image = tester.widget<Image>(imageFinder);
    final resizedImage = image.image as ResizeImage;
    expect(
      (resizedImage.imageProvider as AssetImage).assetName,
      'assets/logos/authenticators/google.png',
    );
    expect(image.fit, BoxFit.cover);
    expect(resizedImage.width, (40 * tester.view.devicePixelRatio).ceil());
    expect(find.text('G'), findsNothing);
  });

  testWidgets('provider chưa nhận diện fallback về ký tự đầu', (tester) async {
    await tester.pumpWidget(
      app(AccountAvatar(issuer: 'HyperZ', logoCatalog: catalog())),
    );

    expect(find.text('H'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(
      tester.getSemantics(find.byType(AccountAvatar)),
      matchesSemantics(label: 'Tài khoản HyperZ', isImage: true),
    );
  });

  testWidgets('issuer rỗng fallback về shield', (tester) async {
    await tester.pumpWidget(
      app(AccountAvatar(issuer: ' ', logoCatalog: catalog())),
    );

    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(AccountAvatar)),
      matchesSemantics(label: 'Tài khoản xác thực', isImage: true),
    );
  });

  testWidgets('asset decode lỗi vẫn fallback và không làm hỏng avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AccountAvatar(
          issuer: 'Broken',
          logoCatalog: catalog(
            mapping: const {'broken': 'not-bundled'},
            assetPaths: const {'assets/logos/authenticators/not-bundled.png'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flutter decode được upstream JPEG mang đuôi png', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AccountAvatar(
          issuer: 'Asana',
          logoCatalog: catalog(
            mapping: const {'asana': 'asana'},
            assetPaths: const {'assets/logos/authenticators/asana.png'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('provider-logo-asana')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
