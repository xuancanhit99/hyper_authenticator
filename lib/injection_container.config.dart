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
import 'features/auth/data/datasources/auth_remote_data_source.dart' as _i767;
import 'features/auth/data/repositories/auth_repository_impl.dart' as _i111;
import 'features/auth/domain/repositories/auth_repository.dart' as _i1015;
import 'features/auth/presentation/bloc/auth_bloc.dart' as _i363;
import 'features/authenticator/data/datasources/authenticator_local_data_source.dart'
    as _i674;
import 'features/authenticator/data/repositories/authenticator_repository_impl.dart'
    as _i166;
import 'features/authenticator/domain/repositories/authenticator_repository.dart'
    as _i608;
import 'features/authenticator/domain/usecases/add_account.dart' as _i356;
import 'features/authenticator/domain/usecases/delete_account.dart' as _i523;
import 'features/authenticator/domain/usecases/generate_totp_code.dart'
    as _i216;
import 'features/authenticator/domain/usecases/get_accounts.dart' as _i572;
import 'features/authenticator/domain/usecases/update_account.dart' as _i827;
import 'features/authenticator/presentation/bloc/accounts_bloc.dart' as _i467;
import 'features/authenticator/presentation/bloc/local_auth_bloc.dart' as _i534;
import 'features/settings/presentation/bloc/settings_bloc.dart' as _i421;
import 'features/sync/data/datasources/encrypted_vault_remote_data_source.dart'
    as _i667;
import 'features/sync/data/datasources/vault_key_store.dart' as _i493;
import 'features/sync/data/repositories/encrypted_sync_metadata_repository_impl.dart'
    as _i961;
import 'features/sync/data/repositories/encrypted_vault_repository_impl.dart'
    as _i32;
import 'features/sync/data/repositories/vault_key_repository_impl.dart'
    as _i733;
import 'features/sync/domain/repositories/encrypted_sync_metadata_repository.dart'
    as _i126;
import 'features/sync/domain/repositories/encrypted_vault_repository.dart'
    as _i949;
import 'features/sync/domain/repositories/vault_key_repository.dart' as _i776;
import 'features/sync/domain/services/vault_cipher.dart' as _i981;
import 'features/sync/domain/usecases/encrypted_vault_sync_usecase.dart'
    as _i564;
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
    gh.lazySingleton<_i981.VaultCipher>(() => _i981.VaultCipher());
    gh.lazySingleton<_i454.SupabaseClient>(() => registerModule.supabaseClient);
    gh.lazySingleton<_i152.LocalAuthentication>(
      () => registerModule.localAuthentication,
    );
    gh.lazySingleton<_i558.FlutterSecureStorage>(
      () => registerModule.flutterSecureStorage,
    );
    gh.lazySingleton<_i706.Uuid>(() => registerModule.uuid);
    gh.factory<_i421.SettingsBloc>(
      () => _i421.SettingsBloc(
        sharedPreferences: gh<_i460.SharedPreferences>(),
        localAuthentication: gh<_i152.LocalAuthentication>(),
      ),
    );
    gh.lazySingleton<_i674.AuthenticatorLocalDataSource>(
      () => _i674.AuthenticatorLocalDataSourceImpl(
        secureStorage: gh<_i558.FlutterSecureStorage>(),
        uuid: gh<_i706.Uuid>(),
      ),
    );
    gh.lazySingleton<_i493.VaultKeyStore>(
      () => _i493.VaultKeyStore(
        gh<_i558.FlutterSecureStorage>(),
        gh<_i981.VaultCipher>(),
      ),
    );
    gh.lazySingleton<_i534.LocalAuthBloc>(
      () => _i534.LocalAuthBloc(
        auth: gh<_i152.LocalAuthentication>(),
        sharedPreferences: gh<_i460.SharedPreferences>(),
      ),
    );
    gh.lazySingleton<_i126.EncryptedSyncMetadataRepository>(
      () => _i961.EncryptedSyncMetadataRepositoryImpl(
        gh<_i460.SharedPreferences>(),
      ),
    );
    gh.lazySingleton<_i767.AuthRemoteDataSource>(
      () => _i767.AuthRemoteDataSourceImpl(
        gh<_i454.SupabaseClient>(),
        gh<_i828.AppConfig>(),
      ),
    );
    gh.lazySingleton<_i667.EncryptedVaultRemoteDataSource>(
      () => _i667.EncryptedVaultRemoteDataSource(gh<_i454.SupabaseClient>()),
    );
    gh.lazySingleton<_i608.AuthenticatorRepository>(
      () => _i166.AuthenticatorRepositoryImpl(
        localDataSource: gh<_i674.AuthenticatorLocalDataSource>(),
      ),
    );
    gh.lazySingleton<_i776.VaultKeyRepository>(
      () => _i733.VaultKeyRepositoryImpl(gh<_i493.VaultKeyStore>()),
    );
    gh.lazySingleton<_i949.EncryptedVaultRepository>(
      () => _i32.EncryptedVaultRepositoryImpl(
        gh<_i667.EncryptedVaultRemoteDataSource>(),
      ),
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
    gh.lazySingleton<_i827.UpdateAccount>(
      () => _i827.UpdateAccount(gh<_i608.AuthenticatorRepository>()),
    );
    gh.lazySingleton<_i1015.AuthRepository>(
      () => _i111.AuthRepositoryImpl(
        remoteDataSource: gh<_i767.AuthRemoteDataSource>(),
      ),
    );
    gh.lazySingleton<_i564.EncryptedVaultSyncUseCase>(
      () => _i564.EncryptedVaultSyncUseCase(
        gh<_i1015.AuthRepository>(),
        gh<_i608.AuthenticatorRepository>(),
        gh<_i949.EncryptedVaultRepository>(),
        gh<_i776.VaultKeyRepository>(),
        gh<_i126.EncryptedSyncMetadataRepository>(),
        gh<_i981.VaultCipher>(),
      ),
    );
    gh.lazySingleton<_i467.AccountsBloc>(
      () => _i467.AccountsBloc(
        getAccounts: gh<_i572.GetAccounts>(),
        addAccount: gh<_i356.AddAccount>(),
        deleteAccount: gh<_i523.DeleteAccount>(),
        updateAccount: gh<_i827.UpdateAccount>(),
      ),
    );
    gh.lazySingleton<_i363.AuthBloc>(
      () => _i363.AuthBloc(
        gh<_i1015.AuthRepository>(),
        gh<_i460.SharedPreferences>(),
      ),
    );
    gh.factory<_i416.SyncBloc>(
      () => _i416.SyncBloc(
        gh<_i564.EncryptedVaultSyncUseCase>(),
        gh<_i467.AccountsBloc>(),
      ),
    );
    return this;
  }
}

class _$RegisterModule extends _i212.RegisterModule {}
