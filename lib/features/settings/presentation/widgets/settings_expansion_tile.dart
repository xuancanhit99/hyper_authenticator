import 'package:flutter/material.dart';

/// An advanced Settings disclosure inside an already separated card.
///
/// [ExpansionTile] otherwise adds top and bottom borders while expanded. That
/// border is useful for a list, but visually conflicts with this app's card
/// hierarchy and can look misaligned when the tile is inset below a ListTile.
class SettingsExpansionTile extends StatelessWidget {
  const SettingsExpansionTile({
    required this.title,
    required this.children,
    this.leading,
    this.subtitle,
    this.tilePadding,
    this.childrenPadding,
    super.key,
  });

  final Widget title;
  final List<Widget> children;
  final Widget? leading;
  final Widget? subtitle;
  final EdgeInsetsGeometry? tilePadding;
  final EdgeInsetsGeometry? childrenPadding;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: leading,
    title: title,
    subtitle: subtitle,
    tilePadding: tilePadding,
    childrenPadding: childrenPadding,
    // The parent card and intentional gaps express grouping. Avoid Flutter's
    // state-dependent default borders, which only appear after expansion.
    shape: const Border(),
    collapsedShape: const Border(),
    children: children,
  );
}
