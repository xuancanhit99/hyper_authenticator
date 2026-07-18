abstract final class TotpValidator {
  static final RegExp _base32Pattern = RegExp(r'^[A-Z2-7]+=*$');
  static const Set<String> supportedAlgorithms = {'SHA1', 'SHA256', 'SHA512'};

  static String normalizeSecret(String value) {
    final secret = value.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
    if (secret.isEmpty || !_base32Pattern.hasMatch(secret)) {
      throw const FormatException('Secret key không đúng định dạng Base32.');
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
      throw const FormatException('Số chữ số OTP phải nằm trong khoảng 6–8.');
    }
    if (period <= 0) {
      throw const FormatException('Chu kỳ OTP phải lớn hơn 0 giây.');
    }
  }
}
