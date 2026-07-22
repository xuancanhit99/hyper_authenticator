import 'dart:convert';
import 'dart:io';

import 'package:hyper_authenticator/core/config/public_runtime_config.dart';

const allowedKeys = <String>{
  'SUPABASE_URL',
  'SUPABASE_PUBLISHABLE_KEY',
  'SUPABASE_ANON_KEY',
  'PASSWORD_RECOVERY_URL',
  'ALLOW_INSECURE_PLAINTEXT_SYNC',
};

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln(
      'Cách dùng: dart run tool/agent/check_release_config.dart <env-file>',
    );
    exitCode = 64;
    return;
  }

  final file = File(arguments.single);
  if (!file.existsSync()) {
    stderr.writeln('Không tìm thấy release config file.');
    exitCode = 66;
    return;
  }

  try {
    final values = _readValues(file);
    final unknownKeys = values.keys.toSet().difference(allowedKeys);
    if (unknownKeys.isNotEmpty) {
      throw const FormatException(
        'Release config chỉ được chứa public client variables',
      );
    }

    final publishableKey = values['SUPABASE_PUBLISHABLE_KEY'];
    final legacyAnonKey = values['SUPABASE_ANON_KEY'];
    if (publishableKey != null && legacyAnonKey != null) {
      throw const FormatException(
        'Chỉ cấu hình một trong SUPABASE_PUBLISHABLE_KEY hoặc SUPABASE_ANON_KEY',
      );
    }

    final plaintextFlag = values['ALLOW_INSECURE_PLAINTEXT_SYNC'] ?? 'false';
    if (plaintextFlag != 'true' && plaintextFlag != 'false') {
      throw const FormatException(
        'ALLOW_INSECURE_PLAINTEXT_SYNC phải là true hoặc false',
      );
    }

    PublicRuntimeConfig.validate(
      supabaseUrl: values['SUPABASE_URL'] ?? '',
      supabasePublishableKey: publishableKey ?? legacyAnonKey ?? '',
      passwordRecoveryUrl: values['PASSWORD_RECOVERY_URL'] ?? '',
      allowInsecurePlaintextSync: plaintextFlag == 'true',
      releaseMode: true,
    );
  } on FormatException catch (error) {
    stderr.writeln('Release config không hợp lệ: ${error.message}');
    exitCode = 1;
    return;
  } on StateError catch (error) {
    stderr.writeln('Release config không hợp lệ: ${error.message}');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Release config pass: chỉ chứa public key, HTTPS URL và plaintext path đã retired.',
  );
}

Map<String, String> _readValues(File file) {
  final content = file.readAsStringSync();
  if (content.trimLeft().startsWith('{')) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON root phải là object');
    }
    return decoded.map((key, value) {
      if (value is! String && value is! bool) {
        throw const FormatException('Mọi JSON define phải là string hoặc bool');
      }
      return MapEntry(key, value.toString());
    });
  }

  final result = <String, String>{};
  for (final indexedLine in content.split('\n').indexed) {
    final lineNumber = indexedLine.$1 + 1;
    final line = indexedLine.$2.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator <= 0) {
      throw FormatException('Dòng $lineNumber không theo format KEY=value');
    }
    final key = line.substring(0, separator).trim();
    var value = line.substring(separator + 1).trim();
    if (!RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(key)) {
      throw FormatException('Tên biến ở dòng $lineNumber không hợp lệ');
    }
    if (result.containsKey(key)) {
      throw FormatException('Biến $key bị khai báo lặp');
    }
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}
