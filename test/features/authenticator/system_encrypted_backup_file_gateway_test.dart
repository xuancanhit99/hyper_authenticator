import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/features/authenticator/data/services/system_encrypted_backup_file_gateway.dart';
import 'package:hyper_authenticator/features/authenticator/domain/repositories/encrypted_backup_file_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    SystemEncryptedBackupFileGateway.androidChannelName,
  );
  const gateway = SystemEncryptedBackupFileGateway();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android dùng document picker native và báo saved', () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return 'saved';
        });

    final bytes = Uint8List.fromList([1, 2, 3]);
    final result = await gateway.saveBackup(
      bytes: bytes,
      suggestedName: 'TEST_ONLY-backup.hyauth',
    );

    expect(result, BackupFileSaveResult.saved);
    expect(capturedCall?.method, 'saveEncryptedBackup');
    expect(capturedCall?.arguments, <String, Object>{
      'bytes': bytes,
      'suggestedName': 'TEST_ONLY-backup.hyauth',
    });
  });

  test('Android giữ nguyên trạng thái cancelled từ document picker', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'cancelled');

    final result = await gateway.saveBackup(
      bytes: Uint8List.fromList([1]),
      suggestedName: 'TEST_ONLY-backup.hyauth',
    );

    expect(result, BackupFileSaveResult.cancelled);
  });

  test('Android từ chối trạng thái native không hợp lệ', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'unexpected');

    expect(
      () => gateway.saveBackup(
        bytes: Uint8List.fromList([1]),
        suggestedName: 'TEST_ONLY-backup.hyauth',
      ),
      throwsA(isA<BackupFileIoException>()),
    );
  });
}
