import 'package:flutter/material.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({required this.issuer, this.size = 40, super.key});

  final String issuer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalizedIssuer = issuer.trim();
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      label: normalizedIssuer.isEmpty
          ? 'Tài khoản xác thực'
          : 'Tài khoản $normalizedIssuer',
      image: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: normalizedIssuer.isEmpty
              ? colorScheme.surfaceContainerHighest
              : _backgroundColor(normalizedIssuer, colorScheme),
          shape: BoxShape.circle,
        ),
        child: normalizedIssuer.isEmpty
            ? Icon(
                Icons.shield_outlined,
                size: size * 0.55,
                color: colorScheme.onSurfaceVariant,
              )
            : Text(
                normalizedIssuer.characters.first.toUpperCase(),
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

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
