abstract final class TotpValidator {
  static final RegExp _base32Pattern = RegExp(r'^[A-Z2-7]+=*$');
  static const Set<String> supportedAlgorithms = {'SHA1', 'SHA256', 'SHA512'};

  static String normalizeSecret(String value) {
    final secret = value.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    if (secret.isEmpty || !_base32Pattern.hasMatch(secret)) {
      throw const FormatException(
        'Khóa thiết lập không đúng định dạng Base32.',
      );
    }
    return secret;
  }

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
