import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';

/// Base class for UseCases in Clean Architecture.
///
/// Defines a standard contract for executing a specific business logic operation.
/// [Result] represents the return type of the use case (on success).
/// [Params] represents the input parameters required by the use case.
abstract class UseCase<Result, Params> {
  Future<Either<Failure, Result>> call(Params params);
}

/// Represents the absence of parameters for a use case.
class NoParams extends Equatable {
  @override
  List<Object?> get props => [];
}
