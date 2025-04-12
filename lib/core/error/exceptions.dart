// lib/core/constants.dart
/// Represents errors originating from server-side operations (API calls, database interactions).
class ServerException implements Exception {
  final String message;

  const ServerException(this.message);

  @override
  String toString() => 'ServerException: $message';
}

/// Represents errors specific to Authentication operations originating from the server.
/// Inherits from ServerException for categorization.
class AuthServerException extends ServerException {
  const AuthServerException(super.message);

  @override
  String toString() => 'AuthServerException: $message';
}

/// Represents errors originating from local cache operations (e.g., SharedPreferences, local DB).
class CacheException implements Exception {
  final String message;

  const CacheException(this.message);

  @override
  String toString() => 'CacheException: $message';
}

/// Represents errors related to network connectivity issues.
class NetworkException implements Exception {
  final String message;

  const NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

/// Represents errors when parsing data (e.g., JSON decoding failed).
class ParsingException implements Exception {
  final String message;

  const ParsingException(this.message);

  @override
  String toString() => 'ParsingException: $message';
}

/// A generic exception for unexpected errors during OCR processing.
class OcrProcessingException implements Exception {
  final String message;

  const OcrProcessingException(this.message);

  @override
  String toString() => 'OcrProcessingException: $message';
}

// Add other specific exception types as needed for your application.
// For example:
// class DatabaseException implements Exception {}
// class FileSystemException implements Exception {}
