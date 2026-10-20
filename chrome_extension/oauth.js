// Local MV3 bridge: only the configured Supabase authorize endpoint can open
// the identity window. No tokens are sent to a web page or extension messaging.
(() => {
  let pending = false;
  const redirectUrl = () => chrome.identity.getRedirectURL('auth/callback');
  globalThis.hyperGoogleOAuth = Object.freeze({
    redirectUrl,
    async authorize(value) {
      if (pending) throw new Error('Sign-in already pending.');
      const url = new URL(value);
      if (url.origin !== 'https://supabase-api.vnpay.dev' ||
          url.pathname !== '/auth/v1/authorize' || url.username || url.password ||
          url.searchParams.get('provider') !== 'google' ||
          url.searchParams.get('redirect_to') !== redirectUrl() ||
          url.searchParams.get('code_challenge_method') !== 's256' ||
          !url.searchParams.get('code_challenge')) {
        throw new Error('Invalid authorization request.');
      }
      pending = true;
      try {
        const callback = await chrome.identity.launchWebAuthFlow({url: url.href, interactive: true});
        if (!callback) throw new Error('Sign-in cancelled.');
        const actual = new URL(callback);
        const expected = new URL(redirectUrl());
        if (actual.origin !== expected.origin || actual.pathname !== expected.pathname ||
            actual.username || actual.password || actual.hash) {
          throw new Error('Invalid OAuth callback.');
        }
        return callback;
      } catch (_) {
        throw new Error('Google sign-in was not completed.');
      } finally {
        pending = false;
      }
    },
  });
})();
