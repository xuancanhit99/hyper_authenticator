import 'package:flutter/material.dart';

const privacyShieldOverlayKey = ValueKey<String>('privacy-shield-overlay');
const privacyShieldBackgroundKey = ValueKey<String>(
  'privacy-shield-background',
);
const privacyShieldSemanticsLabel =
    'Nội dung xác thực đang được ẩn để bảo vệ quyền riêng tư.';

/// Che nội dung nhạy cảm khi ứng dụng không còn ở foreground.
///
/// Widget giữ nguyên cây con để không làm mất state, nhưng chặn pointer, focus,
/// animation và semantics cho tới khi lifecycle quay lại [AppLifecycleState.resumed].
class PrivacyShield extends StatefulWidget {
  const PrivacyShield({required this.child, super.key});

  final Widget child;

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  late bool _isObscured;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Linux headless và một số desktop runner khởi tạo binding ở `detached`
    // nhưng không phát `resumed`. Chỉ che sau một lifecycle signal thực tế để
    // không khóa UI ngay khi bootstrap.
    _isObscured = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldObscure = state != AppLifecycleState.resumed;
    if (shouldObscure) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (shouldObscure == _isObscured || !mounted) {
      return;
    }
    setState(() => _isObscured = shouldObscure);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeSemantics(
        excluding: _isObscured,
        child: ExcludeFocus(
          excluding: _isObscured,
          child: TickerMode(
            enabled: !_isObscured,
            child: AbsorbPointer(absorbing: _isObscured, child: widget.child),
          ),
        ),
      ),
      if (_isObscured)
        const Positioned.fill(
          child: AbsorbPointer(child: _PrivacyShieldOverlay()),
        ),
    ],
  );
}

class _PrivacyShieldOverlay extends StatelessWidget {
  const _PrivacyShieldOverlay();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = theme.scaffoldBackgroundColor.withValues(alpha: 1);
    final accent = Color.alphaBlend(
      scheme.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.14 : 0.08,
      ),
      background,
    ).withValues(alpha: 1);

    return Semantics(
      key: privacyShieldOverlayKey,
      container: true,
      label: privacyShieldSemanticsLabel,
      child: ExcludeSemantics(
        child: ColoredBox(
          key: privacyShieldBackgroundKey,
          // Keep a fully opaque base layer underneath every decoration. Never
          // blur/sample the sensitive route that this widget is covering.
          color: background,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[background, accent, background],
                stops: const <double>[0, 0.48, 1],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final minHeight = (constraints.maxHeight - 64).clamp(
                    0.0,
                    double.infinity,
                  );
                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PrivacyShieldBrandMark(
                                background: scheme.surfaceContainerHigh,
                                border: scheme.outlineVariant,
                                accent: scheme.primary,
                                onAccent: scheme.onPrimary,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Hyper Authenticator',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Nội dung đang được bảo vệ',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Quay lại ứng dụng để tiếp tục.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyShieldBrandMark extends StatelessWidget {
  const _PrivacyShieldBrandMark({
    required this.background,
    required this.border,
    required this.accent,
    required this.onAccent,
  });

  final Color background;
  final Color border;
  final Color accent;
  final Color onAccent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    height: 88,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: background.withValues(alpha: 1),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: border.withValues(alpha: 1)),
          ),
          child: Center(
            child: Image.asset(
              'assets/logos/hyper-logo-green-non-bg-alt.png',
              width: 54,
              height: 54,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.shield_outlined, size: 48, color: accent),
            ),
          ),
        ),
        Positioned(
          right: -5,
          bottom: -5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(
                  context,
                ).scaffoldBackgroundColor.withValues(alpha: 1),
                width: 3,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.lock_rounded, size: 16, color: onAccent),
            ),
          ),
        ),
      ],
    ),
  );
}
