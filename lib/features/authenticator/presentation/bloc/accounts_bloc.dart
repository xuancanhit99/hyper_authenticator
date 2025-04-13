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
    final failureOrAccount = await addAccount(
      AddAccountParams(
        issuer: event.issuer,
        accountName: event.accountName,
        secretKey: event.secretKey,
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
}
