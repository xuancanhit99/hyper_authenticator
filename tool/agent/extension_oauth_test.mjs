import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import assert from 'node:assert/strict';
import {test} from 'node:test';

const source = readFileSync(new URL('../../chrome_extension/oauth.js', import.meta.url), 'utf8');
const redirect = 'https://test.chromiumapp.org/auth/callback';
function bridge(launch) {
  const context = {URL, chrome: {identity: {
    getRedirectURL: () => redirect,
    launchWebAuthFlow: launch,
  }}};
  runInNewContext(source, context);
  return context.hyperGoogleOAuth;
}
function authorizeUrl() {
  const url = new URL('https://supabase-api.vnpay.dev/auth/v1/authorize');
  url.search = new URLSearchParams({provider: 'google', redirect_to: redirect,
    code_challenge_method: 's256', code_challenge: 'TEST_ONLY_CHALLENGE'});
  return url;
}
test('identity bridge rejects unauthorized origins, redirects and missing PKCE before launch', async () => {
  let calls = 0;
  const api = bridge(async () => { calls++; return redirect + '?code=TEST_ONLY'; });
  for (const change of [
    u => {u.hostname = 'evil.invalid';},
    u => {u.pathname = '/auth/v1/token';},
    u => {u.username = 'user';},
    u => {u.searchParams.set('provider', 'github');},
    u => {u.searchParams.set('redirect_to', 'https://evil.invalid');},
    u => {u.searchParams.delete('code_challenge');},
    u => {u.searchParams.set('code_challenge_method', 'plain');},
  ]) {
    const url = authorizeUrl(); change(url);
    await assert.rejects(api.authorize(url.href));
  }
  assert.equal(calls, 0);
  assert.equal(await api.authorize(authorizeUrl().href), redirect + '?code=TEST_ONLY');
  assert.equal(calls, 1);
});
test('identity bridge rejects concurrent flows and recovers after cancellation', async () => {
  let resolve;
  const api = bridge(() => new Promise(r => {resolve = r;}));
  const first = api.authorize(authorizeUrl().href);
  await assert.rejects(api.authorize(authorizeUrl().href), /pending/);
  resolve(undefined);
  await assert.rejects(first, /not completed/);
  const retry = api.authorize(authorizeUrl().href);
  resolve(redirect + '?code=TEST_ONLY');
  assert.equal(await retry, redirect + '?code=TEST_ONLY');
});
test('identity bridge rejects mismatched or token-bearing callbacks and redacts provider errors', async () => {
  for (const callback of ['https://evil.invalid/auth/callback?code=TEST_ONLY',
    redirect + '/wrong?code=TEST_ONLY', redirect + '#access_token=TEST_ONLY']) {
    await assert.rejects(bridge(async () => callback).authorize(authorizeUrl().href), /not completed/);
  }
  await assert.rejects(bridge(async () => {throw Error('SENSITIVE_PROVIDER_ERROR');})
    .authorize(authorizeUrl().href), e => !e.message.includes('SENSITIVE'));
});
