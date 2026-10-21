import assert from 'node:assert/strict';
import test from 'node:test';
import { chromeDebugEndpoint } from './chrome_debug_endpoint.mjs';

test('accepts only the isolated Chrome loopback port and page path', () => {
  const url = 'ws://127.0.0.1:45678/devtools/page/TEST-ONLY-1234';
  assert.equal(chromeDebugEndpoint(url, 45678), url);
});

test('rejects remote hosts, alternate ports, credentials and URL decorations', () => {
  for (const url of [
    'ws://example.invalid:45678/devtools/page/test',
    'ws://localhost:45678/devtools/page/test',
    'ws://127.0.0.1:45679/devtools/page/test',
    'wss://127.0.0.1:45678/devtools/page/test',
    'ws://test@127.0.0.1:45678/devtools/page/test',
    'ws://127.0.0.1:45678/devtools/page/test?redirect=remote',
    'ws://127.0.0.1:45678/devtools/page/test#fragment',
    'ws://127.0.0.1:45678/devtools/browser/test',
    'ws://127.0.0.1:45678/devtools/page/../../remote',
  ]) {
    assert.throws(() => chromeDebugEndpoint(url, 45678), /Unexpected/);
  }
  for (const port of [0, -1, 65536, 1.5, '45678']) {
    assert.throws(() => chromeDebugEndpoint('ws://127.0.0.1:45678/devtools/page/test', port), /Invalid/);
  }
});
