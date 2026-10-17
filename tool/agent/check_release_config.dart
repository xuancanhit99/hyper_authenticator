import 'dart:convert';
import 'dart:io';

import 'package:hyper_authenticator/core/config/public_runtime_config.dart';

const allowedKeys = <String>{
  'SUPABASE_URL',
  'SUPABASE_PUBLISHABLE_KEY',
  'SUPABASE_ANON_KEY',
  'PASSWORD_RECOVERY_URL',
};

void main(List<String> arguments) {
  final bool requireCloud;
  final String configPath;
  if (arguments.length == 1 && arguments.single != '--require-cloud') {
    requireCloud = false;
    configPath = arguments.single;
  } else if (arguments.length == 2 && arguments.first == '--require-cloud') {
    requireCloud = true;
    configPath = arguments.last;
  } else {
    stderr.writeln(
      'Cách dùng: dart run tool/agent/check_release_config.dart '
      '[--require-cloud] <env-file>',
    );
    exitCode = 64;
    return;
  }

  final file = File(configPath);
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

    final config = PublicRuntimeConfig.validate(
      supabaseUrl: values['SUPABASE_URL'] ?? '',
      supabasePublishableKey: publishableKey ?? legacyAnonKey ?? '',
      passwordRecoveryUrl: values['PASSWORD_RECOVERY_URL'] ?? '',
      releaseMode: true,
    );
    if (requireCloud && !config.cloudEnabled) {
      throw StateError(
        'Build này bắt buộc đủ public cloud config; local-only không hợp lệ',
      );
    }
    stdout.writeln(
      config.cloudEnabled
          ? 'Release config pass: cloud dùng public key và HTTPS URL.'
          : 'Release config pass: local-only, không cấu hình cloud.',
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
