import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/authenticator/domain/entities/authenticator_account.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/sync_remote_data_source.dart';
import 'package:injectable/injectable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String accountsTableName = 'synced_accounts'; // Define table name

@LazySingleton(as: SyncRemoteDataSource)
class SupabaseSyncRemoteDataSourceImpl implements SyncRemoteDataSource {
  final SupabaseClient supabaseClient;

  SupabaseSyncRemoteDataSourceImpl({required this.supabaseClient});

  String _getCurrentUserId() {
    final user = supabaseClient.auth.currentUser;
    if (user == null) {
      throw AuthException(
        'User not logged in',
      ); // Or a more specific ServerException
    }
    return user.id;
  }

  @override
  Future<List<AuthenticatorAccount>> downloadAccounts() async {
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

      final accounts =
          data.map((json) => AuthenticatorAccount.fromJson(json)).toList();
      return accounts;
    } on PostgrestException catch (e) {
      // Handle potential Supabase errors (e.g., table not found, RLS issues)
      print('Supabase Error downloading accounts: ${e.message}'); // Log error
      throw ServerException(
        'Failed to download accounts from Supabase: ${e.message}',
      );
    } catch (e) {
      // Handle other errors (e.g., network issues, unexpected format)
      print(
        'Unexpected Error downloading accounts: ${e.toString()}',
      ); // Log error
      throw ServerException(
        'An unexpected error occurred during download: ${e.toString()}',
      );
    }
  }

  @override
  Future<void> uploadAccounts(List<AuthenticatorAccount> accounts) async {
    final userId = _getCurrentUserId();
    try {
      // 1. Delete existing accounts for the user (simple overwrite strategy)
      await supabaseClient
          .from(accountsTableName)
          .delete()
          .eq('user_id', userId);

      // 2. Insert new accounts if the list is not empty
      if (accounts.isNotEmpty) {
        final List<Map<String, dynamic>> dataToInsert =
            accounts.map((account) {
              final json = account.toJson();
              // Map the 'id' from AuthenticatorAccount to 'account_id' column in Supabase
              json['account_id'] = json.remove('id'); // Rename the key
              json['user_id'] = userId; // Add user_id to each record
              return json;
            }).toList();

        await supabaseClient.from(accountsTableName).insert(dataToInsert);
      }
    } on PostgrestException catch (e) {
      print('Supabase Error uploading accounts: ${e.message}');
      throw ServerException(
        'Failed to upload accounts to Supabase: ${e.message}',
      );
    } catch (e) {
      print('Unexpected Error uploading accounts: ${e.toString()}');
      throw ServerException(
        'An unexpected error occurred during upload: ${e.toString()}',
      );
    }
  }

  @override
  Future<bool> hasRemoteData() async {
    final userId = _getCurrentUserId();
    try {
      final response = await supabaseClient
          .from(accountsTableName)
          .select('id') // Select only one column for efficiency
          .eq('user_id', userId)
          .limit(1); // Only need to know if at least one exists

      // Check if the response list is not empty
      return response.isNotEmpty;
    } on PostgrestException catch (e) {
      print('Supabase Error checking remote data: ${e.message}');
      // If RLS prevents access or table doesn't exist, treat as no data? Or throw?
      // For now, let's throw, as it indicates a setup issue.
      throw ServerException('Failed to check remote data: ${e.message}');
    } catch (e) {
      print('Unexpected Error checking remote data: ${e.toString()}');
      throw ServerException(
        'An unexpected error occurred while checking remote data: ${e.toString()}',
      );
    }
  }
}
