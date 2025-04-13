import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:otp/otp.dart'; // Import the OTP library
import 'package:injectable/injectable.dart'; // Add import

// Define a specific Failure for TOTP generation errors

// Define a specific Failure for TOTP generation errors
class TotpGenerationFailure extends Failure {
  const TotpGenerationFailure(String message) : super(message);
}

@injectable // Register use case
class GenerateTotpCode implements UseCase<String, GenerateTotpCodeParams> {
  GenerateTotpCode(); // No repository needed

  @override
  Future<Either<Failure, String>> call(GenerateTotpCodeParams params) async {
    try {
      // Map the algorithm string to the Algorithm enum required by the otp package
      Algorithm algorithmEnum;
      switch (params.algorithm.toUpperCase()) {
        case 'SHA256':
          algorithmEnum = Algorithm.SHA256;
          break;
        case 'SHA512':
          algorithmEnum = Algorithm.SHA512;
          break;
        case 'SHA1':
        default: // Default to SHA1 if unknown or not specified
          algorithmEnum = Algorithm.SHA1;
          break;
      }

      final code = OTP.generateTOTPCodeString(
        params.secretKey,
        DateTime.now().millisecondsSinceEpoch,
        // Pass parameters explicitly
        interval: params.period,
        length: params.digits,
        algorithm: algorithmEnum,
        isGoogle: true, // Keep true for Google Authenticator compatibility
      );
      // Ensure the code is padded with leading zeros if necessary (OTP package usually handles this)
      // Example manual padding (if needed): code = code.padLeft(6, '0');
      return Right(code);
    } catch (e) {
      // Catch potential errors from the OTP library (e.g., invalid secret format)
      return Left(
        TotpGenerationFailure('Failed to generate TOTP code: ${e.toString()}'),
      );
    }
  }
}

class GenerateTotpCodeParams extends Equatable {
  final String secretKey; // Base32 encoded secret key
  final String algorithm;
  final int digits;
  final int period;

  const GenerateTotpCodeParams({
    required this.secretKey,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  @override
  List<Object?> get props => [secretKey, algorithm, digits, period];
}
