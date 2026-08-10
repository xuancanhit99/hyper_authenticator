import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/services/provider_logo_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProviderLogoCatalog', () {
    test('resolve exact issuer, .com normalization và first-word fallback', () {
      final catalog = ProviderLogoCatalog.fromData(
        mapping: const {
          'google': 'google',
          'binance': 'binance',
          'namehero.com': 'namehero',
        },
        assetPaths: const {
          'assets/logos/authenticators/google.png',
          'assets/logos/authenticators/binance.png',
          'assets/logos/authenticators/namehero.png',
        },
      );

      expect(
        catalog.logoAssetForIssuer(' Google '),
        'assets/logos/authenticators/google.png',
      );
      expect(
        catalog.logoAssetForIssuer('Google.com'),
        'assets/logos/authenticators/google.png',
      );
      expect(
        catalog.logoAssetForIssuer('Binance US.com'),
        'assets/logos/authenticators/binance.png',
      );
      expect(
        catalog.logoAssetForIssuer('namehero.com'),
        'assets/logos/authenticators/namehero.png',
      );
    });

    test('resolve đúng tên asset phân biệt hoa thường và local override', () {
      final catalog = ProviderLogoCatalog.fromData(
        mapping: const {'beyondtrust': 'beyondtrust', 'toontown': 'toonwtown'},
        assetPaths: const {
          'assets/logos/authenticators/BeyondTrust.png',
          'assets/logos/authenticators/toontown.png',
        },
        overrides: const {'toonwtown': 'toontown'},
      );

      expect(
        catalog.logoAssetForIssuer('BeyondTrust'),
        'assets/logos/authenticators/BeyondTrust.png',
      );
      expect(
        catalog.logoAssetForIssuer('ToonTown'),
        'assets/logos/authenticators/toontown.png',
      );
    });

    test('mapping thiếu asset và issuer lạ fallback bằng null', () {
      final catalog = ProviderLogoCatalog.fromData(
        mapping: const {'broken': 'missing'},
        assetPaths: const {'assets/logos/authenticators/google.png'},
      );

      expect(catalog.logoAssetForIssuer('broken'), isNull);
      expect(catalog.logoAssetForIssuer('unknown'), isNull);
      expect(catalog.logoAssetForIssuer(''), isNull);
    });

    test('reject asset name collision không phân biệt hoa thường', () {
      expect(
        () => ProviderLogoCatalog.fromData(
          mapping: const {'service': 'service'},
          assetPaths: const {
            'assets/logos/authenticators/Service.png',
            'assets/logos/authenticators/service.png',
          },
        ),
        throwsFormatException,
      );
    });

    test('bundled catalog load được provider cũ và mới', () async {
      final catalog = ProviderLogoCatalog.fromData(
        mapping: const {'placeholder': 'placeholder'},
        assetPaths: const {'assets/logos/authenticators/placeholder.png'},
      );

      await catalog.load();

      expect(
        catalog.logoAssetForIssuer('Google'),
        'assets/logos/authenticators/google.png',
      );
      expect(
        catalog.logoAssetForIssuer('Vercel'),
        'assets/logos/authenticators/vercel.png',
      );
      expect(
        catalog.logoAssetForIssuer('Xfers-SG'),
        'assets/logos/authenticators/xfers-icon.png',
      );
    });
  });
}
