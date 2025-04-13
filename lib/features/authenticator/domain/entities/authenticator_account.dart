import 'package:equatable/equatable.dart';

/// Represents a single account stored in the authenticator app.
class AuthenticatorAccount extends Equatable {
  final String id; // Unique identifier for storage (e.g., generated UUID)
  final String issuer; // Service provider (e.g., "Google", "GitHub")
  final String accountName; // User identifier (e.g., "user@example.com")
  final String secretKey; // Base32 encoded secret key

  // Optional parameters from otpauth URI (using defaults for now)
  // final String algorithm; // e.g., "SHA1", "SHA256", "SHA512" (default: SHA1)
  // final int digits; // e.g., 6, 8 (default: 6)
  // final int period; // e.g., 30, 60 (default: 30)

  const AuthenticatorAccount({
    required this.id,
    required this.issuer,
    required this.accountName,
    required this.secretKey,
  });

  @override
  List<Object?> get props => [id, issuer, accountName, secretKey];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'issuer': issuer,
      'accountName': accountName,
      'secretKey': secretKey,
    };
  }

  factory AuthenticatorAccount.fromJson(Map<String, dynamic> json) {
    return AuthenticatorAccount(
      id: json['id'] as String,
      issuer: json['issuer'] as String,
      accountName: json['accountName'] as String,
      secretKey: json['secretKey'] as String,
    );
  }
}
