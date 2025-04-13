import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart'; // For PlatformException
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import SharedPreferences
import 'package:injectable/injectable.dart';

part 'local_auth_event.dart';
part 'local_auth_state.dart';

// Key must match the one used in SettingsBloc
const String _biometricPrefKey = 'biometric_enabled';

@lazySingleton // Change to LazySingleton
class LocalAuthBloc extends Bloc<LocalAuthEvent, LocalAuthState> {
  final LocalAuthentication auth;
  final SharedPreferences sharedPreferences; // Add dependency

  LocalAuthBloc({
    required this.auth,
    required this.sharedPreferences, // Add to constructor
  }) : super(LocalAuthInitial()) {
    on<CheckLocalAuth>(_onCheckLocalAuth);
    on<Authenticate>(_onAuthenticate);
    on<RelockAppRequested>(_onRelockAppRequested);
    on<ResetAuthStatus>(_onResetAuthStatus); // Register reset handler
  }

  Future<void> _onCheckLocalAuth(
    CheckLocalAuth event,
    Emitter<LocalAuthState> emit,
  ) async {
    // Prevent re-checking if already successfully authenticated in this session
    if (state is LocalAuthSuccess) {
      print("[LocalAuthBloc] Already authenticated, skipping check.");
      return; // Don't re-evaluate if already successfully authenticated
    }
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      // Check both device capability AND user preference
      final bool isBiometricEnabled =
          sharedPreferences.getBool(_biometricPrefKey) ?? false;

      if (canAuthenticate && isBiometricEnabled) {
        // Require auth only if supported AND enabled by user
        emit(LocalAuthRequired());
      } else {
        // If not supported OR not enabled, authentication is not required
        emit(LocalAuthSuccess()); // Treat as success (no lock screen)
        // Note: LocalAuthUnavailable might be emitted if canAuthenticate is false,
        // but LocalAuthSuccess covers both cases where lock is not needed.
      }
    } catch (e) {
      emit(
        LocalAuthError(
          'Error checking local authentication availability: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> _onAuthenticate(
    Authenticate event,
    Emitter<LocalAuthState> emit,
  ) async {
    try {
      final bool didAuthenticate = await auth.authenticate(
        localizedReason: 'Please authenticate to access your accounts',
        options: const AuthenticationOptions(
          stickyAuth: true, // Keep prompt open on app switch
          // biometricOnly: false, // Allow PIN/Password if biometrics fail/unavailable
        ),
      );

      if (didAuthenticate) {
        emit(LocalAuthSuccess());
      } else {
        // User cancelled or failed authentication
        // Stay in LocalAuthRequired state or emit a specific failure state?
        // For simplicity, stay in LocalAuthRequired, user needs to trigger again.
        // Optionally emit an error: emit(LocalAuthError('Authentication failed or cancelled.'));
        emit(LocalAuthRequired()); // Stay in required state
      }
    } on PlatformException catch (e) {
      // Handle specific errors like passcodeNotSet, notAvailable, etc.
      emit(
        LocalAuthError(
          'Local authentication error: ${e.message} (Code: ${e.code})',
        ),
      );
    } catch (e) {
      emit(
        LocalAuthError(
          'An unexpected error occurred during authentication: ${e.toString()}',
        ),
      );
    }
  }

  // Handler for the new event to force re-locking
  Future<void> _onRelockAppRequested(
    RelockAppRequested event,
    Emitter<LocalAuthState> emit,
  ) async {
    // No guard for LocalAuthSuccess here, we explicitly want to re-lock
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      final bool isBiometricEnabled =
          sharedPreferences.getBool(_biometricPrefKey) ?? false;

      if (canAuthenticate && isBiometricEnabled) {
        print(
          "[LocalAuthBloc] Relock requested and conditions met. Emitting LocalAuthRequired.",
        );
        emit(LocalAuthRequired());
      } else {
        // If conditions aren't met (e.g., user disabled biometrics while app was paused),
        // ensure the state reflects that lock is not needed.
        print(
          "[LocalAuthBloc] Relock requested but conditions not met. Emitting LocalAuthSuccess.",
        );
        emit(LocalAuthSuccess());
      }
    } catch (e) {
      emit(LocalAuthError('Error during relock request: ${e.toString()}'));
    }
  }

  // Handler to reset the auth state, typically called when app pauses
  void _onResetAuthStatus(ResetAuthStatus event, Emitter<LocalAuthState> emit) {
    // Only reset if the state is not already initial or required (to avoid unnecessary emits)
    if (state is! LocalAuthInitial && state is! LocalAuthRequired) {
      print("[LocalAuthBloc] Resetting auth status to Initial.");
      emit(LocalAuthInitial());
    } else {
      print(
        "[LocalAuthBloc] Reset requested but state is already Initial/Required. No change.",
      );
    }
  }
} // Close the class definition here
