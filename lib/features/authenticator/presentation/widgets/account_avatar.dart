import 'package:flutter/material.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/services/provider_logo_catalog.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    required this.issuer,
    this.size = 40,
    this.logoCatalog,
    super.key,
  });

  final String issuer;
  final double size;
  final ProviderLogoCatalog? logoCatalog;

  @override
  Widget build(BuildContext context) {
    final normalizedIssuer = issuer.trim();
    final colorScheme = Theme.of(context).colorScheme;
    final logoAssetPath = (logoCatalog ?? ProviderLogoCatalog.instance)
        .logoAssetForIssuer(normalizedIssuer);
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).ceil();

    return Semantics(
      label: normalizedIssuer.isEmpty
          ? 'Tài khoản xác thực'
          : 'Tài khoản $normalizedIssuer',
      image: true,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: logoAssetPath != null || normalizedIssuer.isEmpty
              ? colorScheme.surfaceContainerHighest
              : _backgroundColor(normalizedIssuer, colorScheme),
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
        ),
        child: ClipOval(
          clipBehavior: Clip.antiAlias,
          child: logoAssetPath == null
              ? _fallbackContent(
                  normalizedIssuer: normalizedIssuer,
                  colorScheme: colorScheme,
                )
              : Image.asset(
                  logoAssetPath,
                  key: Key('provider-logo-${normalizedIssuer.toLowerCase()}'),
                  width: size,
                  height: size,
                  cacheWidth: cacheWidth,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => _fallbackContent(
                    normalizedIssuer: normalizedIssuer,
                    colorScheme: colorScheme,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _fallbackContent({
    required String normalizedIssuer,
    required ColorScheme colorScheme,
  }) => normalizedIssuer.isEmpty
      ? Icon(
          Icons.shield_outlined,
          size: size * 0.55,
          color: colorScheme.onSurfaceVariant,
        )
      : Center(
          child: Text(
            normalizedIssuer.characters.first.toUpperCase(),
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontSize: size * 0.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

  Color _backgroundColor(String value, ColorScheme colorScheme) {
    final checksum = value.toLowerCase().codeUnits.fold<int>(
      0,
      (sum, codeUnit) => (sum + codeUnit) % 360,
    );
    return HSLColor.fromAHSL(
      1,
      checksum.toDouble(),
      0.55,
      colorScheme.brightness == Brightness.dark ? 0.42 : 0.38,
    ).toColor();
  }
}
