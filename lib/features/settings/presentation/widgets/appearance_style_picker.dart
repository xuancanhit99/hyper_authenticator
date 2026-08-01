import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_style_palette.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';

/// Settings section for picking the visual style and light/dark mode.
///
/// Reads and mutates the app-wide [ThemeCubit]; changes apply immediately and
/// persist across restarts.
class AppearanceStylePicker extends StatelessWidget {
  const AppearanceStylePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final cubit = context.read<ThemeCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(
          leading: Icon(Icons.palette_outlined),
          title: Text('Giao diện'),
          subtitle: Text('Đổi phong cách và chế độ sáng tối, áp dụng ngay.'),
        ),
        RadioGroup<AppStyle>(
          groupValue: themeState.style,
          onChanged: (style) {
            if (style != null) cubit.setStyle(style);
          },
          child: Column(
            children: [
              for (final style in AppStyle.values)
                Semantics(
                  key: Key('app-style-${style.name}'),
                  container: true,
                  button: true,
                  selected: style == themeState.style,
                  inMutuallyExclusiveGroup: true,
                  label: '${style.label}. ${style.description}',
                  onTap: () => cubit.setStyle(style),
                  // RadioListTile's merged semantics can expose only the
                  // trailing control bounds when a tall tile is clipped by a
                  // sliver at text scale 200%. Keep one explicit full-tile
                  // target and treat the visual radio as decorative here.
                  child: ExcludeSemantics(
                    child: RadioListTile<AppStyle>(
                      value: style,
                      controlAffinity: ListTileControlAffinity.trailing,
                      title: Text(style.label),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(style.description),
                          const SizedBox(height: 8),
                          _StyleSwatch(style: style),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          // Wrap thay vì SegmentedButton: mỗi chip giữ intrinsic width và tự
          // xuống dòng, nên không vỡ layout ở viewport hẹp với text scale lớn.
          child: Wrap(
            key: const Key('theme-mode-selector'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (mode, label, icon) in const [
                (ThemeMode.system, 'Hệ thống', Icons.brightness_auto_outlined),
                (ThemeMode.light, 'Sáng', Icons.light_mode_outlined),
                (ThemeMode.dark, 'Tối', Icons.dark_mode_outlined),
              ])
                ChoiceChip(
                  key: Key('theme-mode-${mode.name}'),
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  selected: themeState.mode == mode,
                  onSelected: (_) => cubit.setThemeMode(mode),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Light/dark background halves with the style's primary color as center dot.
class _StyleSwatch extends StatelessWidget {
  const _StyleSwatch({required this.style});

  final AppStyle style;

  @override
  Widget build(BuildContext context) {
    final light = AppStylePalette.of(style, Brightness.light);
    final dark = AppStylePalette.of(style, Brightness.dark);
    final borderColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.15);

    return Container(
      width: 44,
      height: 28,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(child: ColoredBox(color: light.background)),
              Expanded(child: ColoredBox(color: dark.background)),
            ],
          ),
          Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
