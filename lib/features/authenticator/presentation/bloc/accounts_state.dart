part of 'accounts_bloc.dart';

/// Represents the state of the authenticator accounts list and operations.
abstract class AccountsState extends Equatable {
  const AccountsState();

  @override
  List<Object?> get props => [];
}

/// Initial state, before accounts are loaded.
class AccountsInitial extends AccountsState {}

/// State while accounts are being loaded from storage.
class AccountsLoading extends AccountsState {}

/// Add operation đã persist thành công; không chứa account để tránh đưa secret
/// vào state/log ngoài nhu cầu của UI.
class AccountAddSuccess extends AccountsState {
  const AccountAddSuccess();
}

/// Update operation đã persist thành công; không chứa account để tránh đưa secret
/// vào state/log ngoài nhu cầu của UI.
class AccountUpdateSuccess extends AccountsState {
  final Object operationToken;

  const AccountUpdateSuccess(this.operationToken);

  @override
  List<Object?> get props => [operationToken];

  @override
  String toString() => 'AccountUpdateSuccess(operationToken: [OPAQUE])';
}

/// Update operation thất bại; bind lỗi với đúng request mà không mang account.
class AccountUpdateFailure extends AccountsState {
  final Object operationToken;
  final String message;

  const AccountUpdateFailure(this.operationToken, this.message);

  @override
  List<Object?> get props => [operationToken, message];

  @override
  String toString() =>
      'AccountUpdateFailure('
      'operationToken: [OPAQUE], message: [REDACTED])';
}

/// State when accounts have been successfully loaded.
class AccountsLoaded extends AccountsState {
  final List<AuthenticatorAccount> accounts;

  const AccountsLoaded(this.accounts);

  @override
  List<Object?> get props => [accounts];
}

/// State when an error occurs during loading, adding, or deleting accounts.
class AccountsError extends AccountsState {
  final String message;

  const AccountsError(this.message);

  @override
  List<Object?> get props => [message];
}

// Optional: Add a specific delete-success state if UI feedback needs to be bound
// to that operation instead of the subsequent list reload.
// class AccountDeletedSuccess extends AccountsState {}
