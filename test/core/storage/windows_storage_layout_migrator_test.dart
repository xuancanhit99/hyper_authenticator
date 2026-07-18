import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/core/storage/windows_storage_layout_migrator.dart';
import 'package:hyper_authenticator/core/storage/windows_storage_migration_exception.dart';

void main() {
  late Directory sandbox;
  late Directory source;
  late Directory target;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('ha-storage-migration-');
    source = Directory('${sandbox.path}${Platform.pathSeparator}source');
    target = Directory('${sandbox.path}${Platform.pathSeparator}target');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  WindowsStorageLayoutMigrator createMigrator() => WindowsStorageLayoutMigrator(
    sourceDirectory: source,
    targetDirectory: target,
  );

  String child(Directory directory, String name) =>
      '${directory.path}${Platform.pathSeparator}$name';

  test('không tạo target hoặc marker khi source không tồn tại', () async {
    await createMigrator().migrate();

    expect(await target.exists(), isFalse);
  });

  test('copy file hợp lệ, giữ source và ghi marker', () async {
    await source.create(recursive: true);
    await File(
      child(source, 'flutter_secure_storage.dat'),
    ).writeAsBytes([1, 2, 3]);
    await File(child(source, 'legacy.secure')).writeAsBytes([4, 5]);
    await File(
      child(source, 'shared_preferences.json'),
    ).writeAsString('{"theme":"dark"}');
    await File(child(source, 'ignored.txt')).writeAsString('không copy');

    await createMigrator().migrate();

    expect(
      await File(child(target, 'flutter_secure_storage.dat')).readAsBytes(),
      [1, 2, 3],
    );
    expect(await File(child(target, 'legacy.secure')).readAsBytes(), [4, 5]);
    expect(
      await File(child(target, 'shared_preferences.json')).readAsString(),
      '{"theme":"dark"}',
    );
    expect(await File(child(target, 'ignored.txt')).exists(), isFalse);
    expect(
      await File(
        child(target, WindowsStorageLayoutMigrator.markerFileName),
      ).readAsString(),
      'v1\n',
    );
    expect(await File(child(source, 'legacy.secure')).readAsBytes(), [4, 5]);
  });

  test('marker ngăn import lặp lại và không overwrite target', () async {
    await source.create(recursive: true);
    await target.create(recursive: true);
    await File(child(source, 'vault.secure')).writeAsBytes([1]);
    await File(child(target, 'vault.secure')).writeAsBytes([2]);
    await File(
      child(target, WindowsStorageLayoutMigrator.markerFileName),
    ).writeAsString('v1\n');

    await createMigrator().migrate();

    expect(await File(child(target, 'vault.secure')).readAsBytes(), [2]);
  });

  test('từ chối hai vault khác nhau và không overwrite target', () async {
    await source.create(recursive: true);
    await target.create(recursive: true);
    await File(child(source, 'vault.secure')).writeAsBytes([1]);
    await File(child(target, 'vault.secure')).writeAsBytes([2]);

    await expectLater(
      createMigrator().migrate(),
      throwsA(isA<WindowsStorageMigrationConflict>()),
    );

    expect(await File(child(target, 'vault.secure')).readAsBytes(), [2]);
    expect(
      await File(
        child(target, WindowsStorageLayoutMigrator.markerFileName),
      ).exists(),
      isFalse,
    );
  });

  test('chấp nhận hai vault có cùng tên và byte', () async {
    await source.create(recursive: true);
    await target.create(recursive: true);
    await File(child(source, 'vault.secure')).writeAsBytes([1, 2]);
    await File(child(target, 'vault.secure')).writeAsBytes([1, 2]);

    await createMigrator().migrate();

    expect(
      await File(
        child(target, WindowsStorageLayoutMigrator.markerFileName),
      ).exists(),
      isTrue,
    );
  });

  test('không theo symlink file trong source', () async {
    if (Platform.isWindows) {
      return;
    }
    await source.create(recursive: true);
    final outside = File(child(sandbox, 'outside.secure'));
    await outside.writeAsBytes([9]);
    await Link(child(source, 'linked.secure')).create(outside.path);
    await File(child(source, 'shared_preferences.json')).writeAsString('{}');

    await createMigrator().migrate();

    expect(await File(child(target, 'linked.secure')).exists(), isFalse);
    expect(await outside.readAsBytes(), [9]);
  });

  test('lỗi giữa chừng rollback file đã tạo và không ghi marker', () async {
    await source.create(recursive: true);
    await target.create(recursive: true);
    await File(child(source, 'a.secure')).writeAsBytes([1]);
    await File(child(source, 'b.secure')).writeAsBytes([2]);
    await Directory(child(target, 'b.secure')).create();

    await expectLater(
      createMigrator().migrate(),
      throwsA(isA<WindowsStorageMigrationFailure>()),
    );

    expect(await File(child(target, 'a.secure')).exists(), isFalse);
    expect(await Directory(child(target, 'b.secure')).exists(), isTrue);
    expect(await File(child(source, 'a.secure')).readAsBytes(), [1]);
    expect(await File(child(source, 'b.secure')).readAsBytes(), [2]);
    expect(
      await File(
        child(target, WindowsStorageLayoutMigrator.markerFileName),
      ).exists(),
      isFalse,
    );
  });
}
