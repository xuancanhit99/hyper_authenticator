// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;
import 'package:local_auth/local_auth.dart' as _i152;
import 'package:shared_preferences/shared_preferences.dart' as _i460;
import 'package:supabase_flutter/supabase_flutter.dart' as _i454;
import 'package:uuid/uuid.dart' as _i706;

import 'core/config/app_config.dart' as _i828;
import 'core/storage/secure_key_value_store.dart' as _i697;
import 'features/auth/data/datasources/auth_remote_data_source.dart' as _i767;
import 'features/auth/data/repositories/auth_repository_impl.dart' as _i111;
import 'features/auth/domain/repositories/auth_repository.dart' as _i1015;
import 'features/auth/presentation/bloc/auth_bloc.dart' as _i363;
import 'features/authenticator/data/datasources/authenticator_local_data_source.dart'
    as _i674;
import 'features/authenticator/data/repositories/authenticator_repository_impl.dart'
    as _i166;
import 'features/authenticator/data/services/local_sensitive_action_authenticator.dart'
    as _i387;
import 'features/authenticator/domain/repositories/authenticator_repository.dart'
    as _i608;
import 'features/authenticator/domain/services/sensitive_action_authenticator.dart'
    as _i217;
import 'features/authenticator/domain/usecases/add_account.dart' as _i356;
import 'features/authenticator/domain/usecases/delete_account.dart' as _i523;
import 'features/authenticator/domain/usecases/generate_totp_code.dart'
    as _i216;
import 'features/authenticator/domain/usecases/get_accounts.dart' as _i572;
import 'features/authenticator/domain/usecases/import_accounts.dart' as _i125;
import 'features/authenticator/domain/usecases/update_account.dart' as _i827;
import 'features/authenticator/presentation/bloc/accounts_bloc.dart' as _i467;
import 'features/authenticator/presentation/bloc/local_auth_bloc.dart' as _i534;
import 'features/settings/presentation/bloc/settings_bloc.dart' as _i421;
import 'features/sync/data/datasources/account_sync_metadata_store.dart'
    as _i194;
import 'features/sync/data/datasources/cloud_account_remote_data_source.dart'
    as _i146;
import 'features/sync/data/datasources/supabase_account_sync_signal_repository.dart'
    as _i139;
import 'features/sync/domain/repositories/account_sync_metadata_repository.dart'
    as _i41;
import 'features/sync/domain/repositories/account_sync_signal_repository.dart'
    as _i1000;
import 'features/sync/domain/repositories/cloud_account_repository.dart'
    as _i817;
import 'features/sync/domain/usecases/synchronize_accounts.dart' as _i747;
import 'features/sync/presentation/bloc/sync_bloc.dart' as _i416;
import 'injection_module.dart' as _i212;

extension GetItInjectableX on _i174.GetIt {
  // initializes the registration of main-scope dependencies inside of GetIt
  Future<_i174.GetIt> init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) async {
    final gh = _i526.GetItHelper(this, environment, environmentFilter);
    final registerModule = _$RegisterModule();
    gh.factory<_i216.GenerateTotpCode>(() => _i216.GenerateTotpCode());
    await gh.factoryAsync<_i460.SharedPreferences>(
      () => registerModule.sharedPreferences,
      preResolve: true,
    );
    gh.lazySingleton<_i828.AppConfig>(() => _i828.AppConfig.fromEnvironment());
    gh.lazySingleton<_i152.LocalAuthentication>(
      () => registerModule.localAuthentication,
    );
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => registerModule.flutterSecureStorage,
    );
    gh.lazySingleton<_i706.Uuid>(() => registerModule.uuid);
    gh.lazySingleton<_i697.SecureKeyValueStore>(
      () =>
          registerModule.secureKeyValueStore(gh<_i558.FlutterSecureStorage>()),
    );
    gh.factory<_i421.SettingsBloc>(
      () => _i421.SettingsBloc(
        sharedPreferences: gh<_i460.SharedPreferences>(),
        localAuthentication: gh<_i152.LocalAuthentication>(),
      ),
    );
    gh.lazySingleton<_i454.SupabaseClient>(
      () => registerModule.supabaseClient(gh<_i828.AppConfig>()),
    );
    gh.lazySingleton<_i534.LocalAuthBloc>(
      () => _i534.LocalAuthBloc(
        auth: gh<_i152.LocalAuthentication>(),
        sharedPreferences: gh<_i460.SharedPreferences>(),
      ),
    );
    gh.lazySingleton<_i767.AuthRemoteDataSource>(
      () => _i767.AuthRemoteDataSourceImpl(
        gh<_i454.SupabaseClient>(),
        gh<_i828.AppConfig>(),
      ),
    );
    gh.lazySingleton<_i817.CloudAccountRepository>(
      () => _i146.CloudAccountRemoteDataSource(gh<_i454.SupabaseClient>()),
    );
    gh.lazySingleton<_i674.AuthenticatorLocalDataSource>(
      () => _i674.AuthenticatorLocalDataSourceImpl(
        secureStorage: gh<_i697.SecureKeyValueStore>(),
        uuid: gh<_i706.Uuid>(),
      ),
    );
    gh.lazySingleton<_i608.AuthenticatorRepository>(
      () => _i166.AuthenticatorRepositoryImpl(
        localDataSource: gh<_i674.AuthenticatorLocalDataSource>(),
      ),
    );
    gh.lazySingleton<_i1000.AccountSyncSignalRepository>(
      () =>
          _i139.SupabaseAccountSyncSignalRepository(gh<_i454.SupabaseClient>()),
    );
    gh.lazySingleton<_i217.SensitiveActionAuthenticator>(
      () => _i387.LocalSensitiveActionAuthenticator(
        gh<_i152.LocalAuthentication>(),
      ),
    );
    gh.lazySingleton<_i41.AccountSyncMetadataRepository>(
      () => _i194.AccountSyncMetadataStore(gh<_i697.SecureKeyValueStore>()),
    );
    gh.factory<_i356.AddAccount>(
      () => _i356.AddAccount(gh<_i608.AuthenticatorRepository>()),
    );
    gh.factory<_i523.DeleteAccount>(
      () => _i523.DeleteAccount(gh<_i608.AuthenticatorRepository>()),
    );
    gh.factory<_i572.GetAccounts>(
      () => _i572.GetAccounts(gh<_i608.AuthenticatorRepository>()),
    );
    gh.factory<_i125.ImportAccounts>(
      () => _i125.ImportAccounts(gh<_i608.AuthenticatorRepository>()),
    );
    gh.lazySingleton<_i827.UpdateAccount>(
      () => _i827.UpdateAccount(gh<_i608.AuthenticatorRepository>()),
    );
    gh.lazySingleton<_i467.AccountsBloc>(
      () => _i467.AccountsBloc(
        getAccounts: gh<_i572.GetAccounts>(),
        addAccount: gh<_i356.AddAccount>(),
        deleteAccount: gh<_i523.DeleteAccount>(),
        updateAccount: gh<_i827.UpdateAccount>(),
        importAccounts: gh<_i125.ImportAccounts>(),
      ),
    );
    gh.lazySingleton<_i1015.AuthRepository>(
      () => _i111.AuthRepositoryImpl(
        remoteDataSource: gh<_i767.AuthRemoteDataSource>(),
      ),
    );
    gh.lazySingleton<_i363.AuthBloc>(
      () => _i363.AuthBloc(gh<_i1015.AuthRepository>()),
    );
    gh.lazySingleton<_i747.AccountSynchronizer>(
      () => _i747.SynchronizeAccounts(
        gh<_i1015.AuthRepository>(),
        gh<_i608.AuthenticatorRepository>(),
        gh<_i817.CloudAccountRepository>(),
        gh<_i41.AccountSyncMetadataRepository>(),
      ),
    );
    gh.lazySingleton<_i416.SyncBloc>(
      () => _i416.SyncBloc(
        gh<_i747.AccountSynchronizer>(),
        gh<_i1000.AccountSyncSignalRepository>(),
        gh<_i363.AuthBloc>(),
        gh<_i467.AccountsBloc>(),
      ),
    );
    return this;
  }
}

class _$RegisterModule extends _i212.RegisterModule {}
