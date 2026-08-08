import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hyper_authenticator/core/widgets/responsive_content.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';

class LockScreenPage extends StatefulWidget {
  const LockScreenPage({super.key});

  @override
  State<LockScreenPage> createState() => _LockScreenPageState();
}

class _LockScreenPageState extends State<LockScreenPage> {
  bool _authTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAuthenticationIfNeeded();
    });
  }

  void _triggerAuthenticationIfNeeded() {
    if (!mounted) return;

    final localAuthBloc = context.read<LocalAuthBloc>();
    if (localAuthBloc.state is LocalAuthRequired && !_authTriggered) {
      setState(() => _authTriggered = true);
      localAuthBloc.add(Authenticate());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ResponsiveScrollableContent(
        maxWidth: 420,
        child: BlocBuilder<LocalAuthBloc, LocalAuthState>(
          builder: (context, state) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _LockBrandMark(),
              const SizedBox(height: 28),
              Text(
                'Ứng dụng đang được khóa',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Xác thực bằng Face ID, vân tay hoặc mã khóa thiết bị để tiếp tục.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (state is LocalAuthError) ...[
                const SizedBox(height: 20),
                Semantics(
                  liveRegion: true,
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              state.message,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Mở khóa'),
                onPressed: () =>
                    context.read<LocalAuthBloc>().add(Authenticate()),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LockBrandMark extends StatelessWidget {
  const _LockBrandMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(
                child: Image.asset(
                  'assets/logos/hyper-logo-green-non-bg-alt.png',
                  width: 58,
                  height: 58,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.shield_outlined,
                    size: 52,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.lock_rounded, size: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
