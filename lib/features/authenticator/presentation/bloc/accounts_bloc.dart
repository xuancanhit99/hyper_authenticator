import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/error/user_facing_failure.dart';
import 'package:hyper_authenticator/core/usecases/usecase.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/services/totp_uri_parser.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart'; // Import UpdateAccount use case
import 'package:injectable/injectable.dart'; // Moved import here

part 'accounts_event.dart';
part 'accounts_state.dart';

@lazySingleton
class AccountsBloc extends Bloc<AccountsEvent, AccountsState> {
  final GetAccounts getAccounts;
  final AddAccount addAccount;
  final DeleteAccount deleteAccount;
  final UpdateAccount updateAccount; // Added UpdateAccount use case
  final ImportAccounts importAccounts;
  // Note: GenerateTotpCode use case is not needed directly in the Bloc state management.
  // It will be called directly from the UI when displaying codes.

  AccountsBloc({
    required this.getAccounts,
    required this.addAccount,
    required this.deleteAccount,
    required this.updateAccount, // Added to constructor
    required this.importAccounts,
  }) : super(AccountsInitial()) {
    on<LoadAccounts>(_onLoadAccounts);
    on<AddAccountRequested>(_onAddAccountRequested);
    on<DeleteAccountRequested>(_onDeleteAccountRequested);
    on<ImportAccountsRequested>(_onImportAccountsRequested);
    on<UpdateAccountRequested>(
      _onUpdateAccountRequested,
    ); // Added handler for update
  }

  Future<void> _onImportAccountsRequested(
    ImportAccountsRequested event,
    Emitter<AccountsState> emit,
  ) async {
    final result = await importAccounts(ImportAccountsParams(event.accounts));
    result.fold(
      (failure) => emit(
        AccountsError(
          _mapFailureToMessage(failure, UserFailureContext.importAccounts),
        ),
      ),
      (summary) {
        emit(
          AccountImportSuccess(
            importedCount: summary.importedCount,
            duplicateCount: summary.duplicateCount,
          ),
        );
        add(LoadAccounts());
      },
    );
  }

  Future<void> _onLoadAccounts(
    LoadAccounts event,
    Emitter<AccountsState> emit,
  ) async {
    emit(AccountsLoading());
    final failureOrAccounts = await getAccounts(NoParams());
    failureOrAccounts.fold(
      (failure) => emit(
        AccountsError(
          _mapFailureToMessage(failure, UserFailureContext.loadAccounts),
        ),
      ),
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
      (failure) async => emit(
        AccountsError(
          _mapFailureToMessage(failure, UserFailureContext.addAccount),
        ),
      ),
      (_) async {
        emit(const AccountAddSuccess());
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
    final failureOrSuccess = await deleteAccount(
      DeleteAccountParams(accountId: event.accountId),
    );

    await failureOrSuccess.fold(
      (failure) async {
        emit(
          AccountDeleteFailure(
            _mapFailureToMessage(failure, UserFailureContext.deleteAccount),
          ),
        );
        add(LoadAccounts());
      },
      (_) async {
        emit(const AccountDeleteSuccess());
        add(LoadAccounts());
      },
    );
  }

  // Helper to convert Failure objects to user-friendly messages
  String _mapFailureToMessage(Failure failure, UserFailureContext context) =>
      userFacingFailureMessage(failure, context: context);

  Future<void> _onUpdateAccountRequested(
    UpdateAccountRequested event,
    Emitter<AccountsState> emit,
  ) async {
    // Optionally emit a loading state specific to updating
    // emit(AccountUpdating());
    final failureOrSuccess = await updateAccount(
      UpdateAccountParams(account: event.account),
    );

    await failureOrSuccess.fold(
      (failure) async => emit(
        AccountUpdateFailure(
          event.operationToken,
          _mapFailureToMessage(failure, UserFailureContext.updateAccount),
        ),
      ),
      (_) async {
        emit(AccountUpdateSuccess(event.operationToken));
        // Reload only after the UI has received the operation-specific success.
        add(LoadAccounts());
      },
    );
  }
}
