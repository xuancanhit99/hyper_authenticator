import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/error/failures.dart';
import 'package:hyper_authenticator/core/theme/app_theme.dart';
import 'package:hyper_authenticator/core/theme/theme_cubit.dart';
import 'package:hyper_authenticator/features/auth/domain/entities/user_entity.dart';
import 'package:hyper_authenticator/features/auth/domain/repositories/auth_repository.dart';
import 'package:hyper_authenticator/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/authenticator_repository.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/add_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/delete_account.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/get_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/import_accounts.dart';
import 'package:hyper_authenticator/features/authenticator/domain/usecases/update_account.dart';
import 'package:hyper_authenticator/features/authenticator/presentation/bloc/accounts_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:hyper_authenticator/features/settings/presentation/pages/settings_page.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_result.dart';
import 'package:hyper_authenticator/features/sync/domain/entities/account_sync_signal.dart';
import 'package:hyper_authenticator/features/sync/domain/repositories/account_sync_signal_repository.dart';
import 'package:hyper_authenticator/features/sync/domain/usecases/synchronize_accounts.dart';
import 'package:hyper_authenticator/features/sync/presentation/bloc/sync_bloc.dart';
import 'package:hyper_authenticator/injection_container.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Settings hiển thị partial và retry về success khi hết mã bị chặn',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await sl.reset();
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final authBloc = AuthBloc(_SignedInAuthRepository());
      final accounts = _UnusedAccountRepository();
      final accountsBloc = AccountsBloc(
        getAccounts: GetAccounts(accounts),
        addAccount: AddAccount(accounts),
        deleteAccount: DeleteAccount(accounts),
        updateAccount: UpdateAccount(accounts),
        importAccounts: ImportAccounts(accounts),
      );
      final synchronizer = _PartialSynchronizer();
      final syncBloc = SyncBloc(
        synchronizer,
        _NoSyncSignals(),
        authBloc,
        accountsBloc,
      );
      final themeCubit = ThemeCubit(preferences);
      addTearDown(() async {
        await syncBloc.close();
        await accountsBloc.close();
        await authBloc.close();
        await themeCubit.close();
        await sl.reset();
      });
      sl.registerSingleton<AppConfig>(
        const AppConfig(
          supabaseUrl: 'https://supabase.example.invalid',
          supabasePublishableKey:
              'TEST_ONLY_PUBLIC_CONFIG_NOT_USED_FOR_NETWORK',
        ),
      );
      sl.registerSingleton<SyncBloc>(syncBloc);
      sl.registerFactory<SettingsBloc>(
        () => SettingsBloc(
          sharedPreferences: preferences,
          localAuthentication: _UnsupportedLocalAuthentication(),
        ),
      );
      authBloc.add(AuthCheckRequested());

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: authBloc),
            BlocProvider<ThemeCubit>.value(value: themeCubit),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(syncBloc.state, isA<SyncPartial>());
      expect(synchronizer.calls, 1);
      expect(find.textContaining('Còn 2 mã chưa đồng bộ'), findsOneWidget);
      expect(
        find.textContaining('Các mã hợp lệ đã được đồng bộ.'),
        findsOneWidget,
      );
      expect(find.textContaining('Đã đồng bộ tự động'), findsNothing);
      expect(tester.takeException(), isNull);

      synchronizer.blockedAccountCount = 0;
      final retry = find.widgetWithText(OutlinedButton, 'Thử đồng bộ lại');
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(synchronizer.calls, 2);
      expect(syncBloc.state, isA<SyncReady>());
      expect(find.textContaining('Còn 2 mã chưa đồng bộ'), findsNothing);
      expect(find.textContaining('Đã đồng bộ tự động'), findsOneWidget);
      expect(find.text('Thử đồng bộ lại'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _PartialSynchronizer implements AccountSynchronizer {
  int calls = 0;
  int blockedAccountCount = 2;

  @override
  Future<Either<Failure, AccountSyncResult>> call() async {
    calls++;
    return Right(
      AccountSyncCompleted(
        completedAt: DateTime.utc(2026, 10, 19),
        uploadedCount: 0,
        downloadedCount: 0,
        deletedCount: 0,
        blockedAccountCount: blockedAccountCount,
      ),
    );
  }
}

class _NoSyncSignals implements AccountSyncSignalRepository {
  @override
  Stream<AccountSyncSignal> watch({required String userId}) =>
      const Stream.empty();
}

class _UnsupportedLocalAuthentication extends LocalAuthentication {
  @override
  Future<bool> get canCheckBiometrics async => false;

  @override
  Future<bool> isDeviceSupported() async => false;
}

class _SignedInAuthRepository implements AuthRepository {
  static const _user = UserEntity(
    id: 'TEST_ONLY_SETTINGS_USER',
    email: 'settings@example.invalid',
    name: 'TEST_ONLY User',
  );

  @override
  UserEntity get currentUserEntity => _user;

  @override
  Stream<UserEntity?> get authEntityChanges => const Stream.empty();

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUserEntity() async =>
      const Right(_user);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected auth operation in Settings test.');
}

class _UnusedAccountRepository implements AuthenticatorRepository {
  @override
  Future<Either<Failure, List<AuthenticatorAccount>>> getAccounts() async =>
      const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected account mutation in Settings test.');
}
