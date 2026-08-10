import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/theme/app_style.dart';
import 'package:hyper_authenticator/core/theme/app_style_palette.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';

/// Compact Settings entry point for changing visual style and brightness mode.
///
/// The persisted enum names remain stable. The sheet only changes display
/// labels and applies each selection immediately through the app-wide cubit.
class AppearanceStylePicker extends StatelessWidget {
  const AppearanceStylePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeCubit>().state;

    return ListTile(
      key: const Key('appearance-picker-tile'),
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Giao diện'),
      subtitle: Text('${state.style.label} · ${_modeSummaryLabel(state.mode)}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showAppearanceSheet(context),
    );
  }

  Future<void> _showAppearanceSheet(BuildContext context) {
    final cubit = context.read<ThemeCubit>();
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          BlocProvider.value(value: cubit, child: const _AppearanceSheet()),
    );
  }
}

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeCubit>().state;
    final cubit = context.read<ThemeCubit>();
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chọn giao diện',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      key: const Key('close-appearance-sheet'),
                      tooltip: 'Đóng',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Phong cách', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final style in AppStyle.values) ...[
                  _StyleOption(
                    style: style,
                    selected: state.style == style,
                    onTap: () => cubit.setStyle(style),
                  ),
                  if (style != AppStyle.values.last) const SizedBox(height: 8),
                ],
                const SizedBox(height: 24),
                Text('Chế độ hiển thị', style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in ThemeMode.values)
                      ChoiceChip(
                        key: Key('theme-mode-choice-${mode.name}'),
                        avatar: Icon(_modeIcon(mode), size: 18),
                        label: Text(_modeLabel(mode)),
                        selected: state.mode == mode,
                        showCheckmark: false,
                        onSelected: (_) => cubit.setThemeMode(mode),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleOption extends StatelessWidget {
  const _StyleOption({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AppStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderColor = selected ? colors.primary : colors.outlineVariant;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('app-style-option-${style.name}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _StylePreview(style: style),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        style.label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        style.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (selected)
                  Icon(Icons.check_circle, color: colors.primary)
                else
                  const SizedBox(width: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small non-interactive preview showing both brightness variants.
class _StylePreview extends StatelessWidget {
  const _StylePreview({required this.style});

  final AppStyle style;

  @override
  Widget build(BuildContext context) {
    final light = AppStylePalette.of(style, Brightness.light);
    final dark = AppStylePalette.of(style, Brightness.dark);

    return ExcludeSemantics(
      child: MediaQuery.withNoTextScaling(
        child: SizedBox(
          key: Key('app-style-preview-${style.name}'),
          width: 56,
          height: 48,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Row(
                  children: [
                    Expanded(
                      child: ColoredBox(
                        color: light.background,
                        child: Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: light.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ColoredBox(
                        color: dark.background,
                        child: Center(
                          child: Text(
                            '12',
                            style: TextStyle(
                              color: dark.otpCode ?? dark.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _modeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Theo hệ thống',
  ThemeMode.light => 'Sáng',
  ThemeMode.dark => 'Tối',
};

String _modeSummaryLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Hệ thống',
  ThemeMode.light => 'Sáng',
  ThemeMode.dark => 'Tối',
};

IconData _modeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};
