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
      final code = OTP.generateTOTPCodeString(
        params.secretKey,
        DateTime.now().millisecondsSinceEpoch,
        // Default OTP parameters (can be made configurable if needed)
        // interval: 30,
        // length: 6,
        // algorithm: Algorithm.SHA1,
        // isGoogle: true, // Handles Base32 padding correctly
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

  const GenerateTotpCodeParams({required this.secretKey});

  @override
  List<Object?> get props => [secretKey];
}
