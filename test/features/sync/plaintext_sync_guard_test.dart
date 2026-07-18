import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/config/app_config.dart';
import 'package:hyper_authenticator/core/error/exceptions.dart';
import 'package:hyper_authenticator/features/sync/data/datasources/supabase_sync_remote_data_source_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseSyncRemoteDataSourceImpl dataSource;

  setUp(() {
    dataSource = SupabaseSyncRemoteDataSourceImpl(
      supabaseClient: SupabaseClient(
        'https://example.invalid',
        'TEST_ONLY_PUBLIC_KEY',
      ),
      appConfig: const AppConfig(
        supabaseUrl: 'https://example.invalid',
        supabasePublishableKey: 'TEST_ONLY_PUBLIC_KEY',
      ),
    );
  });

  test(
    'khóa mọi remote sync trước khi truy cập session hoặc network',
    () async {
      final operations = <Future<Object?> Function()>[
        dataSource.downloadAccounts,
        () => dataSource.uploadAccounts(const []),
        dataSource.hasRemoteData,
        dataSource.getLastUploadTime,
      ];

      for (final operation in operations) {
        await expectLater(
          operation(),
          throwsA(
            isA<ServerException>().having(
              (error) => error.message,
              'message',
              contains('chưa được mã hóa đầu cuối'),
            ),
          ),
        );
      }
    },
  );

  test('release build luôn khóa plaintext sync dù đã opt-in', () {
    const config = AppConfig(
      supabaseUrl: 'https://example.invalid',
      supabasePublishableKey: 'TEST_ONLY_PUBLIC_KEY',
      allowInsecurePlaintextSync: true,
      releaseMode: true,
    );

    expect(config.plaintextSyncAvailable, isFalse);
  });
}
