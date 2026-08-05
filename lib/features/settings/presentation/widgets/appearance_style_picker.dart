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
          dense: true,
          visualDensity: VisualDensity(vertical: -2),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: 'Phong cách giao diện',
                value: themeState.style.label,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Phong cách',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AppStyle>(
                      key: const Key('app-style-dropdown'),
                      value: themeState.style,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(16),
                      onChanged: (style) {
                        if (style != null) cubit.setStyle(style);
                      },
                      items: [
                        for (final style in AppStyle.values)
                          DropdownMenuItem<AppStyle>(
                            key: Key('app-style-option-${style.name}'),
                            value: style,
                            child: Row(
                              children: [
                                _StyleSwatch(style: style),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    style.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Chế độ hiển thị',
                value: _modeLabel(themeState.mode),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Chế độ',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ThemeMode>(
                      key: const Key('theme-mode-dropdown'),
                      value: themeState.mode,
                      isExpanded: true,
                      borderRadius: BorderRadius.circular(16),
                      onChanged: (mode) {
                        if (mode != null) cubit.setThemeMode(mode);
                      },
                      items: [
                        for (final mode in ThemeMode.values)
                          DropdownMenuItem<ThemeMode>(
                            key: Key('theme-mode-option-${mode.name}'),
                            value: mode,
                            child: Row(
                              children: [
                                Icon(_modeIcon(mode), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _modeLabel(mode),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
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
      width: 36,
      height: 24,
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

String _modeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Theo hệ thống',
  ThemeMode.light => 'Sáng',
  ThemeMode.dark => 'Tối',
};

IconData _modeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};
