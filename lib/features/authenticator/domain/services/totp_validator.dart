import 'package:base32/base32.dart';

abstract final class TotpValidator {
  static final RegExp _base32Pattern = RegExp(r'^[A-Z2-7]+=*$');
  static const Set<String> supportedAlgorithms = {'SHA1', 'SHA256', 'SHA512'};

  static String normalizeSecret(String value) {
    final secret = value.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    if (secret.isEmpty || !_base32Pattern.hasMatch(secret)) {
      throw _invalidSecret;
    }

    final paddingIndex = secret.indexOf('=');
    final unpadded = paddingIndex < 0
        ? secret
        : secret.substring(0, paddingIndex);
    final requiredPadding = switch (unpadded.length % 8) {
      0 => 0,
      2 => 6,
      4 => 4,
      5 => 3,
      7 => 1,
      _ => throw _invalidSecret,
    };
    final paddingLength = secret.length - unpadded.length;
    if (paddingLength != 0 && paddingLength != requiredPadding) {
      throw _invalidSecret;
    }

    // The pinned decoder accepts invalid residual groups and nonzero pad bits.
    // Check the quantum above and a canonical round-trip before trusting bytes.
    final bytes = base32.decode(unpadded);
    if (bytes.isEmpty || base32.encode(bytes).replaceAll('=', '') != unpadded) {
      throw _invalidSecret;
    }
    return unpadded;
  }

  static const _invalidSecret = FormatException(
    'Khóa thiết lập không đúng định dạng Base32.',
  );

  static String normalizeAlgorithm(String value) {
    final algorithm = value.trim().toUpperCase();
    if (!supportedAlgorithms.contains(algorithm)) {
      throw FormatException('Thuật toán $algorithm chưa được hỗ trợ.');
    }
    return algorithm;
  }

  static void validateParameters({required int digits, required int period}) {
    if (digits < 6 || digits > 8) {
      throw const FormatException('Số chữ số của mã phải từ 6 đến 8.');
    }
    if (period <= 0 || period > 300) {
      throw const FormatException('Thời gian làm mới phải từ 1 đến 300 giây.');
    }
  }
}
