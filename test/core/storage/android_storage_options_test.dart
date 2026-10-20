import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_authenticator/injection_module.dart';

class _Module extends RegisterModule {}

void main() {
  test('production Android storage preserves namespace and disables reset', () {
    final options = _Module().flutterSecureStorage.aOptions.toMap();
    expect(options['resetOnError'], 'false');
    expect(options['migrateWithBackup'], 'true');
    expect(options['migrateOnAlgorithmChange'], 'true');
    expect(options['storageNamespace'], '');
  });
}
