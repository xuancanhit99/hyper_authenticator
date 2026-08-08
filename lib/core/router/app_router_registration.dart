import 'package:hyper_authenticator/core/router/app_router.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/local_auth_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';

/// Registers the router used by the native and hosted-Web app only.
///
/// The Chrome Extension has an intentionally separate router so its build
/// does not retain camera/QR scanner code that is not allowed in the MV3
/// package until it is bundled locally in a later phase.
void registerDefaultAppRouter() {
  if (sl.isRegistered<AppRouter>()) return;
  sl.registerLazySingleton(
    () => AppRouter(sl<AuthBloc>(), sl<LocalAuthBloc>(), sl()),
  );
}
