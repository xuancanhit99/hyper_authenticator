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

// Optional: Add specific states for Add/Delete success if needed for UI feedback,
// but often just reloading the list (AccountsLoaded) is sufficient.
// class AccountAddedSuccess extends AccountsState {}
// class AccountDeletedSuccess extends AccountsState {}
