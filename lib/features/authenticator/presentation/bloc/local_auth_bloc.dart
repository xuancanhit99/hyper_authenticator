import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart'; // For PlatformException
import 'package:local_auth/local_auth.dart';
import 'package:injectable/injectable.dart'; // Moved import here

part 'local_auth_event.dart';
part 'local_auth_state.dart';

@lazySingleton // Change to LazySingleton
class LocalAuthBloc extends Bloc<LocalAuthEvent, LocalAuthState> {
  final LocalAuthentication auth;

  LocalAuthBloc({required this.auth}) : super(LocalAuthInitial()) {
    on<CheckLocalAuth>(_onCheckLocalAuth);
    on<Authenticate>(_onAuthenticate);
  }

  Future<void> _onCheckLocalAuth(
    CheckLocalAuth event,
    Emitter<LocalAuthState> emit,
  ) async {
    try {
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (canAuthenticate) {
        // If auth is possible, assume it's required initially until passed
        emit(LocalAuthRequired());
      } else {
        // If no auth method is available, treat as unavailable/success (no lock)
        emit(LocalAuthUnavailable());
        // Alternatively, emit LocalAuthSuccess() if unavailable means no lock needed
        // emit(LocalAuthSuccess());
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
}
