import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/sync_remote_data_source.dart';
import 'package:hyper_authenticator/features/sync/data/mappers/supabase_account_mapper.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String accountsTableName = 'synced_accounts';
const String profilesTableName = 'user_profiles'; // Define profiles table name

@LazySingleton(as: SyncRemoteDataSource)
class SupabaseSyncRemoteDataSourceImpl implements SyncRemoteDataSource {
  final SupabaseClient supabaseClient;
  final AppConfig appConfig;

  SupabaseSyncRemoteDataSourceImpl({
    required this.supabaseClient,
    required this.appConfig,
  });

  void _requireExplicitPlaintextSyncOptIn() {
    if (!appConfig.plaintextSyncAvailable) {
      throw const ServerException(
        'Cloud sync đang bị khóa vì remote payload chưa được mã hóa đầu cuối.',
      );
    }
  }

  String _getCurrentUserId() {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw const AuthException('User not logged in');
    }
    return user.id;
  }

  @override
  Future<List<AuthenticatorAccount>> downloadAccounts() async {
    _requireExplicitPlaintextSyncOptIn();
    final userId = _getCurrentUserId();
    try {
      final response = await supabaseClient
          .from(accountsTableName)
          .select()
          .eq('user_id', userId);

      // Supabase v2 returns List<Map<String, dynamic>> directly
      final List<Map<String, dynamic>> data = List<Map<String, dynamic>>.from(
        response,
      );

      final accounts = data.map(SupabaseAccountMapper.fromRow).toList();

      return accounts;
    } on PostgrestException catch (e) {
      throw ServerException(
        'Failed to download accounts from Supabase: ${e.message}',
      );
    } catch (e) {
      throw ServerException(
        'An unexpected error occurred during download: ${e.toString()}',
      );
    }
  }

  @override
  Future<void> uploadAccounts(List<AuthenticatorAccount> accounts) async {
    _requireExplicitPlaintextSyncOptIn();
    final userId = _getCurrentUserId();
    try {
      // 1. Delete existing accounts for the user (simple overwrite strategy)
      await supabaseClient
          .from(accountsTableName)
          .delete()
          .eq('user_id', userId);

      // 2. Insert new accounts if the list is not empty
      if (accounts.isNotEmpty) {
        final List<Map<String, dynamic>> dataToInsert = accounts
            .map(
              (account) => SupabaseAccountMapper.toRow(account, userId: userId),
            )
            .toList();

        await supabaseClient.from(accountsTableName).insert(dataToInsert);
      }
      // The 'updated_at' column is automatically set by 'DEFAULT now()' during INSERT.
      // No explicit update needed here anymore.
    } on PostgrestException catch (e) {
      throw ServerException(
        'Failed to upload accounts to Supabase: ${e.message}',
      );
    } catch (e) {
      throw ServerException(
        'An unexpected error occurred during upload: ${e.toString()}',
      );
    }
  }

  @override
  Future<bool> hasRemoteData() async {
    _requireExplicitPlaintextSyncOptIn();
    final userId = _getCurrentUserId();
    try {
      final response = await supabaseClient
          .from(accountsTableName)
          .select('account_id')
          .eq('user_id', userId)
          .limit(1); // Only need to know if at least one exists

      // Check if the response list is not empty
      return response.isNotEmpty;
    } on PostgrestException catch (e) {
      throw ServerException('Failed to check remote data: ${e.message}');
    } catch (e) {
      throw ServerException(
        'An unexpected error occurred while checking remote data: ${e.toString()}',
      );
    }
  }

  // Removed _updateLastSyncTime helper method as it's no longer needed.
  // The updated_at column in synced_accounts handles this automatically on insert.
  @override
  Future<DateTime?> getLastUploadTime() async {
    _requireExplicitPlaintextSyncOptIn();
    // Get the most recent 'updated_at' timestamp from the user's synced accounts.
    final userId = _getCurrentUserId();
    try {
      final response = await supabaseClient
          .from(accountsTableName)
          .select('updated_at')
          .eq('user_id', userId)
          .order('updated_at', ascending: false) // Get the latest first
          .limit(1) // Only need the latest one
          .maybeSingle(); // Use maybeSingle as user might have no accounts yet

      if (response == null || response['updated_at'] == null) {
        return null;
      }

      return DateTime.tryParse(response['updated_at'] as String);
    } catch (_) {
      return null;
    }
  }
}
