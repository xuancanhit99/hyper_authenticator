/// Callback validation happens before a one-time PKCE code reaches Supabase.
/// Never include callback URLs, provider errors or codes in diagnostics.
String googleOAuthCallbackCode(Uri callback, Uri expected) {
  if (callback.scheme != expected.scheme ||
      callback.host != expected.host ||
      callback.port != expected.port ||
      callback.path != expected.path ||
      callback.userInfo.isNotEmpty ||
      callback.fragment.isNotEmpty) {
    throw const FormatException('Invalid OAuth callback.');
  }
  if (callback.queryParameters.containsKey('error')) {
    throw const FormatException('OAuth was not completed.');
  }
  final codes = callback.queryParametersAll['code'];
  if (codes == null ||
      codes.length != 1 ||
      codes.single.isEmpty ||
      codes.single.length > 4096) {
    throw const FormatException('Missing OAuth authorization code.');
  }
  return codes.single;
}
