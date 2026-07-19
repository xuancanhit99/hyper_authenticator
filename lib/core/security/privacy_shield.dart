import 'package:flutter/material.dart';

const privacyShieldOverlayKey = ValueKey<String>('privacy-shield-overlay');
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
    _isObscured =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
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
        child: TickerMode(
          enabled: !_isObscured,
          child: AbsorbPointer(absorbing: _isObscured, child: widget.child),
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
  Widget build(BuildContext context) => Semantics(
    key: privacyShieldOverlayKey,
    container: true,
    label: privacyShieldSemanticsLabel,
    child: ExcludeSemantics(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 1),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 48),
                SizedBox(height: 16),
                Text(
                  'Hyper Authenticator',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text('Nội dung đã được ẩn', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
