// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as _i558;
import 'package:get_it/get_it.dart' as _i174;
import 'package:http/http.dart' as _i519;
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
import 'features/authenticator/presentation/bloc/accounts_bloc.dart' as _i467;
import 'features/authenticator/presentation/bloc/local_auth_bloc.dart' as _i534;
import 'features/settings/presentation/bloc/settings_bloc.dart' as _i421;
import 'features/sync/data/datasources/supabase_sync_remote_data_source_impl.dart'
    as _i984;
import 'features/sync/data/datasources/sync_remote_data_source.dart' as _i686;
import 'features/sync/data/repositories/sync_repository_impl.dart' as _i345;
import 'features/sync/domain/repositories/sync_repository.dart' as _i800;
import 'features/sync/domain/usecases/download_accounts_usecase.dart' as _i939;
import 'features/sync/domain/usecases/get_last_sync_time_usecase.dart' as _i4;
import 'features/sync/domain/usecases/has_remote_data_usecase.dart' as _i650;
import 'features/sync/domain/usecases/upload_accounts_usecase.dart' as _i392;
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
    gh.lazySingleton<_i828.AppConfig>(() => _i828.AppConfig.fromEnv());
    gh.lazySingleton<_i519.Client>(() => registerModule.httpClient);
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
    gh.lazySingleton<_i686.SyncRemoteDataSource>(
      () => _i984.SupabaseSyncRemoteDataSourceImpl(
        supabaseClient: gh<_i454.SupabaseClient>(),
      ),
    );
    gh.lazySingleton<_i767.AuthRemoteDataSource>(
      () => _i767.AuthRemoteDataSourceImpl(gh<_i454.SupabaseClient>()),
    );
    gh.lazySingleton<_i534.LocalAuthBloc>(
      () => _i534.LocalAuthBloc(
        auth: gh<_i152.LocalAuthentication>(),
        sharedPreferences: gh<_i460.SharedPreferences>(),
      ),
    );
    gh.lazySingleton<_i1015.AuthRepository>(
      () => _i111.AuthRepositoryImpl(
        remoteDataSource: gh<_i767.AuthRemoteDataSource>(),
      ),
    );
    gh.lazySingleton<_i800.SyncRepository>(
      () => _i345.SyncRepositoryImpl(
        remoteDataSource: gh<_i686.SyncRemoteDataSource>(),
      ),
    );
    gh.lazySingleton<_i608.AuthenticatorRepository>(
      () => _i166.AuthenticatorRepositoryImpl(
        localDataSource: gh<_i674.AuthenticatorLocalDataSource>(),
      ),
    );
    gh.lazySingleton<_i4.GetLastSyncTimeUseCase>(
      () => _i4.GetLastSyncTimeUseCase(gh<_i800.SyncRepository>()),
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
    gh.factory<_i363.AuthBloc>(
      () => _i363.AuthBloc(
        gh<_i1015.AuthRepository>(),
        gh<_i460.SharedPreferences>(),
        gh<_i558.FlutterSecureStorage>(),
      ),
    );
    gh.lazySingleton<_i939.DownloadAccountsUseCase>(
      () => _i939.DownloadAccountsUseCase(gh<_i800.SyncRepository>()),
    );
    gh.lazySingleton<_i650.HasRemoteDataUseCase>(
      () => _i650.HasRemoteDataUseCase(gh<_i800.SyncRepository>()),
    );
    gh.lazySingleton<_i392.UploadAccountsUseCase>(
      () => _i392.UploadAccountsUseCase(gh<_i800.SyncRepository>()),
    );
    gh.factory<_i467.AccountsBloc>(
      () => _i467.AccountsBloc(
        getAccounts: gh<_i572.GetAccounts>(),
        addAccount: gh<_i356.AddAccount>(),
        deleteAccount: gh<_i523.DeleteAccount>(),
      ),
    );
    gh.factory<_i416.SyncBloc>(
      () => _i416.SyncBloc(
        gh<_i650.HasRemoteDataUseCase>(),
        gh<_i392.UploadAccountsUseCase>(),
        gh<_i939.DownloadAccountsUseCase>(),
        gh<_i4.GetLastSyncTimeUseCase>(),
        gh<_i467.AccountsBloc>(),
        gh<_i460.SharedPreferences>(),
      ),
    );
    return this;
  }
}

class _$RegisterModule extends _i212.RegisterModule {}
