import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:injectable/injectable.dart'; // Moved import here

part 'accounts_event.dart';
part 'accounts_state.dart';

@injectable // Register Bloc
class AccountsBloc extends Bloc<AccountsEvent, AccountsState> {
  final GetAccounts getAccounts;
  final AddAccount addAccount;
  final DeleteAccount deleteAccount;
  // Note: GenerateTotpCode use case is not needed directly in the Bloc state management.
  // It will be called directly from the UI when displaying codes.

  AccountsBloc({
    required this.getAccounts,
    required this.addAccount,
    required this.deleteAccount,
  }) : super(AccountsInitial()) {
    on<LoadAccounts>(_onLoadAccounts);
    on<AddAccountRequested>(_onAddAccountRequested);
    on<DeleteAccountRequested>(_onDeleteAccountRequested);
    on<ReplaceAccountsEvent>(_onReplaceAccounts); // Added handler
  }

  Future<void> _onLoadAccounts(
    LoadAccounts event,
    Emitter<AccountsState> emit,
  ) async {
    emit(AccountsLoading());
    final failureOrAccounts = await getAccounts(NoParams());
    failureOrAccounts.fold(
      (failure) => emit(AccountsError(_mapFailureToMessage(failure))),
      (accounts) => emit(AccountsLoaded(accounts)),
    );
  }

  Future<void> _onAddAccountRequested(
    AddAccountRequested event,
    Emitter<AccountsState> emit,
  ) async {
    // Optionally emit a loading state specific to adding if needed
    // emit(AccountAdding());
    // Pass all parameters from the event to the AddAccount use case params
    final failureOrAccount = await addAccount(
      AddAccountParams(
        issuer: event.issuer,
        accountName: event.accountName,
        secretKey: event.secretKey,
        algorithm: event.algorithm, // Pass from event
        digits: event.digits, // Pass from event
        period: event.period, // Pass from event
      ),
    );

    await failureOrAccount.fold(
      (failure) async => emit(AccountsError(_mapFailureToMessage(failure))),
      (account) async {
        // After successfully adding, reload the list to show the new account
        add(LoadAccounts()); // Trigger reload
        // Alternatively, if state holds the list, update it directly:
        // if (state is AccountsLoaded) {
        //   final updatedList = List<AuthenticatorAccount>.from((state as AccountsLoaded).accounts)..add(account);
        //   emit(AccountsLoaded(updatedList));
        // } else {
        //    add(LoadAccounts()); // Fallback to reload if state is unexpected
        // }
      },
    );
  }

  Future<void> _onDeleteAccountRequested(
    DeleteAccountRequested event,
    Emitter<AccountsState> emit,
  ) async {
    // Optionally emit a loading state specific to deleting
    // emit(AccountDeleting());
    final failureOrSuccess = await deleteAccount(
      DeleteAccountParams(accountId: event.accountId),
    );

    await failureOrSuccess.fold(
      (failure) async => emit(AccountsError(_mapFailureToMessage(failure))),
      (_) async {
        // After successfully deleting, reload the list
        add(LoadAccounts()); // Trigger reload
        // Alternatively, update state directly:
        // if (state is AccountsLoaded) {
        //   final updatedList = (state as AccountsLoaded).accounts.where((acc) => acc.id != event.accountId).toList();
        //   emit(AccountsLoaded(updatedList));
        // } else {
        //    add(LoadAccounts()); // Fallback
        // }
      },
    );
  }

  // Helper to convert Failure objects to user-friendly messages
  String _mapFailureToMessage(Failure failure) {
    switch (failure.runtimeType) {
      case StorageFailure:
      case AccountNotFoundFailure:
      case ValidationFailure:
        return failure.message;
      // Add mappings for other core failures if necessary
      // case ServerFailure:
      //   return 'Server Error';
      default:
        return 'An unexpected error occurred.';
    }
  }

  Future<void> _onReplaceAccounts(
    ReplaceAccountsEvent event, // Contains downloadedAccounts
    Emitter<AccountsState> emit,
  ) async {
    emit(AccountsLoading()); // Indicate processing state

    // 1. Get current local accounts for comparison
    final failureOrCurrentAccounts = await getAccounts(NoParams());

    await failureOrCurrentAccounts.fold(
      (failure) async {
        // If fetching current accounts fails, emit error and stop
        emit(
          AccountsError(
            'Failed to get current accounts before merging: ${_mapFailureToMessage(failure)}',
          ),
        );
      },
      (currentLocalAccounts) async {
        // Create a set of identifiers for existing local accounts for efficient lookup
        // Using issuer and accountName as the key for comparison (case-insensitive)
        final existingLocalIdentifiers =
            currentLocalAccounts
                .map(
                  (acc) =>
                      '${acc.issuer.toLowerCase()}:${acc.accountName.toLowerCase()}',
                )
                .toSet();

        // 2. Add only the accounts from the server that are not already present locally
        bool hasAddError = false;
        String firstAddErrorMessage = '';
        int addedCount = 0;

        for (final downloadedAccount in event.accounts) {
          final downloadedIdentifier =
              '${downloadedAccount.issuer.toLowerCase()}:${downloadedAccount.accountName.toLowerCase()}';

          // Check if an account with the same issuer/name already exists locally
          if (!existingLocalIdentifiers.contains(downloadedIdentifier)) {
            // If not present, add it
            final addResult = await addAccount(
              AddAccountParams(
                issuer: downloadedAccount.issuer,
                accountName: downloadedAccount.accountName,
                secretKey: downloadedAccount.secretKey,
                algorithm: downloadedAccount.algorithm,
                digits: downloadedAccount.digits,
                period: downloadedAccount.period,
              ),
            );
            await addResult.fold(
              (failure) async {
                if (!hasAddError) {
                  hasAddError = true;
                  firstAddErrorMessage = _mapFailureToMessage(failure);
                }
                print(
                  'Error adding account ${downloadedAccount.accountName} during merge: ${failure.message}',
                );
              },
              (_) async {
                addedCount++;
                // Add the newly added identifier to prevent adding duplicates
                // if the server list somehow contained duplicates itself.
                existingLocalIdentifiers.add(downloadedIdentifier);
              },
            );
          } else {
            print(
              'Skipping account ${downloadedAccount.accountName} as it already exists locally.',
            );
          }
        }

        if (hasAddError) {
          print(
            'Merge finished with errors. First error: $firstAddErrorMessage',
          );
          // Optionally emit a specific state
        }

        print('Merge complete. Added $addedCount new accounts.');

        // 3. Finally, reload the accounts to reflect the merged state
        add(LoadAccounts());
      },
    );
  }
}
