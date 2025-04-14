// lib/core/error/failures.dart
import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

// General failures
class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

// Specific OCR Failures
class OcrParsingFailure extends Failure {
  const OcrParsingFailure(super.message);
}

// Failure for secure storage access errors
class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

// Failure when a specific account is not found in storage
class AccountNotFoundFailure extends Failure {
  const AccountNotFoundFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

// Specific Auth Failures can be added if needed, mapping from Supabase errors
class AuthCredentialsFailure extends Failure {
  const AuthCredentialsFailure(super.message);
}

class AuthServerFailure extends Failure {
  const AuthServerFailure(super.message);
}

// Failure for input validation errors
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

// Failure specific to sync operations (e.g., encryption/decryption issues)
class SyncOperationFailure extends Failure {
  const SyncOperationFailure(super.message);
}
