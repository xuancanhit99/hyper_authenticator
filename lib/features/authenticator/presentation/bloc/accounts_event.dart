part of 'accounts_bloc.dart'; // Assuming accounts_bloc.dart will be created next

abstract class AccountsEvent extends Equatable {
  const AccountsEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load all stored authenticator accounts.
class LoadAccounts extends AccountsEvent {}

/// Event triggered to add a new account (usually after scanning or manual entry).
class AddAccountRequested extends AccountsEvent {
  final String issuer;
  final String accountName;
  final String secretKey;
  final String algorithm;
  final int digits;
  final int period;

  const AddAccountRequested({
    required this.issuer,
    required this.accountName,
    required this.secretKey,
    required this.algorithm,
    required this.digits,
    required this.period,
  });

  @override
  List<Object?> get props => [
    issuer,
    accountName,
    secretKey,
    algorithm,
    digits,
    period,
  ];
}

/// Event to delete an existing account by its ID.
class DeleteAccountRequested extends AccountsEvent {
  final String accountId;

  const DeleteAccountRequested({required this.accountId});

  @override
  List<Object?> get props => [accountId];
}

// Note: We won't have a specific event to generate codes here.
// Code generation will be handled reactively in the UI based on the loaded accounts
// and a timer/ticker, using the GenerateTotpCode use case.
