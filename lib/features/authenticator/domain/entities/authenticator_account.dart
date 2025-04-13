import 'package:equatable/equatable.dart';

/// Represents a single account stored in the authenticator app.
class AuthenticatorAccount extends Equatable {
  final String id; // Unique identifier for storage (e.g., generated UUID)
  final String issuer; // Service provider (e.g., "Google", "GitHub")
  final String accountName; // User identifier (e.g., "user@example.com")
  final String secretKey; // Base32 encoded secret key

  // Parameters from otpauth URI
  final String algorithm; // e.g., "SHA1", "SHA256", "SHA512"
  final int digits; // e.g., 6, 8
  final int period; // e.g., 30, 60

  const AuthenticatorAccount({
    required this.id,
    required this.issuer,
    required this.accountName,
    required this.secretKey,
    this.algorithm = 'SHA1', // Default to SHA1
    this.digits = 6, // Default to 6 digits
    this.period = 30, // Default to 30 seconds
  });

  @override
  List<Object?> get props => [
    id,
    issuer,
    accountName,
    secretKey,
    algorithm,
    digits,
    period,
  ];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'issuer': issuer,
      'accountName': accountName,
      'secretKey': secretKey,
      'algorithm': algorithm,
      'digits': digits,
      'period': period,
    };
  }

  factory AuthenticatorAccount.fromJson(Map<String, dynamic> json) {
    return AuthenticatorAccount(
      id: json['id'] as String,
      issuer: json['issuer'] as String,
      accountName: json['accountName'] as String,
      secretKey: json['secretKey'] as String,
      // Use defaults if values are missing or null
      algorithm: json['algorithm'] as String? ?? 'SHA1',
      digits: json['digits'] as int? ?? 6,
      period: json['period'] as int? ?? 30,
    );
  }
}
