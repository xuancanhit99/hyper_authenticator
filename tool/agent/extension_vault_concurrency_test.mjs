import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

// Real isolated browser contexts sharing one origin/IDB, never the user's profile.
const chrome = process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const source = await readFile(process.env.VAULT_SOURCE || 'chrome_extension/vault.js', 'utf8');
const profile = await mkdtemp(path.join(tmpdir(), 'hyper-vault-test-'));
const barrier = [];
let barrierPassed = false;
const server = createServer((request, response) => {
  if (request.url.startsWith('/barrier?') && !barrierPassed) {
    barrier.push(response);
    if (barrier.length === 2) { barrierPassed = true; barrier.forEach(r => r.end('ok')); }
    return;
  }
  if (request.url === '/vault.js') { response.setHeader('Content-Type', 'text/javascript'); response.end(source); }
  else response.end('<!doctype html><title>TEST ONLY vault</title>');
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const child = spawn(chrome, ['--headless=new', '--no-first-run', '--no-default-browser-check',
  '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], { stdio: 'ignore', windowsHide: true });
const connections = [];
const delay = ms => new Promise(r => setTimeout(r, ms));
async function connect(port) {
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  connections.push(ws);
  let id = 0;
  const pending = new Map();
  ws.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    const promise = pending.get(message.id);
    if (promise) { pending.delete(message.id); message.error ? promise.reject(message.error) : promise.resolve(message.result); }
  };
  const send = (method, params) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`CDP timeout: ${method}`)), 20000);
    pending.set(++id, { resolve: value => { clearTimeout(timer); resolve(value); }, reject: error => { clearTimeout(timer); reject(error); } }); ws.send(JSON.stringify({ id, method, params }));
  });
  const evaluate = async expression => {
    const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || 'Browser evaluation failed');
    return result.result.value;
  };
  await send('Page.enable', {});
  await send('Page.navigate', { url: origin });
  for (let attempt = 0; attempt < 100; attempt++) {
    if (await evaluate(`location.origin === ${JSON.stringify(origin)} && document.readyState === 'complete'`)) break;
    await delay(20);
  }
  await evaluate(`(() => {
    const generate = crypto.subtle.generateKey.bind(crypto.subtle);
    crypto.subtle.generateKey = async (...args) => {
      const key = await generate(...args); await fetch('/barrier?' + crypto.randomUUID()); return key;
    };
  })()`);
  await evaluate(source);
  return evaluate;
}
try {
  let port;
  for (let attempt = 0; attempt < 200; attempt++) {
    try { port = Number((await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]); break; }
    catch { await delay(50); }
  }
  assert.ok(port, 'isolated Chrome did not start');
  const [a, b] = await Promise.all([connect(port), connect(port)]);
  console.log('Browser contexts ready; testing simultaneous cold key initialization.');
  await Promise.all([
    a("hyperExtensionVault.write('TEST_ONLY_A', 'TEST_ONLY_ALPHA')"),
    b("hyperExtensionVault.write('TEST_ONLY_B', 'TEST_ONLY_BETA')"),
  ]);
  const reopened = await connect(port);
  console.log('Cold writes complete; testing reopen and cross-context mutations.');
  assert.equal(await reopened("hyperExtensionVault.read('TEST_ONLY_A')"), 'TEST_ONLY_ALPHA');
  assert.equal(await reopened("hyperExtensionVault.read('TEST_ONLY_B')"), 'TEST_ONLY_BETA');
  const increment = `(async () => {
    for (let i = 0; i < 12; i++) {
      const token = await hyperExtensionVault.beginExclusive();
      try {
        const value = Number(await hyperExtensionVault.read('TEST_ONLY_COUNTER') || 0);
        await Promise.resolve();
        await hyperExtensionVault.write('TEST_ONLY_COUNTER', String(value + 1));
      } finally { await hyperExtensionVault.endExclusive(token); }
    }
  })()`;
  await Promise.all([a(increment), b(increment)]);
  assert.equal(await reopened("hyperExtensionVault.read('TEST_ONLY_COUNTER')"), '24');
  const all = JSON.parse(await reopened('hyperExtensionVault.readAllJson()'));
  assert.equal(all.TEST_ONLY_COUNTER, '24');
  await reopened(`new Promise((resolve, reject) => {
    const request = indexedDB.open('hyper-authenticator-extension-v1', 1);
    request.onsuccess = () => {
      const tx = request.result.transaction('records', 'readwrite');
      const records = tx.objectStore('records');
      const record = records.get('TEST_ONLY_A');
      record.onsuccess = () => {
        new Uint8Array(record.result.ciphertext)[0] ^= 1;
        records.put(record.result, 'TEST_ONLY_A');
      };
      tx.oncomplete = resolve; tx.onerror = reject;
    };
  })`);
  await assert.rejects(() => reopened("hyperExtensionVault.read('TEST_ONLY_A')"), /OperationError/);
  assert.equal(await reopened("hyperExtensionVault.read('TEST_ONLY_B')"), 'TEST_ONLY_BETA');
  await reopened(`new Promise((resolve, reject) => {
    const request = indexedDB.open('hyper-authenticator-extension-v1', 1);
    request.onsuccess = () => {
      const tx = request.result.transaction('keys', 'readwrite');
      tx.objectStore('keys').delete('vault-key');
      tx.oncomplete = resolve; tx.onerror = reject;
    };
  })`);
  const missingKey = await connect(port);
  for (const expression of ["hyperExtensionVault.read('TEST_ONLY_A')", "hyperExtensionVault.write('TEST_ONLY_C', 'TEST_ONLY_GAMMA')"]) {
    await assert.rejects(() => missingKey(expression), /key is missing/);
  }
  await missingKey(`new Promise((resolve, reject) => {
    const request = indexedDB.open('hyper-authenticator-extension-v1', 1);
    request.onsuccess = () => {
      const tx = request.result.transaction('keys', 'readwrite');
      tx.objectStore('keys').put('TEST_ONLY_INVALID_KEY', 'vault-key');
      tx.oncomplete = resolve; tx.onerror = reject;
    };
  })`);
  await assert.rejects(() => missingKey("hyperExtensionVault.read('TEST_ONLY_B')"), /key is invalid/);
  console.log('PASS: real Chrome cold key race, reopen/decrypt, cross-context mutation, tamper/missing/invalid-key preservation.');
} finally {
  connections.forEach(ws => ws.close());
  barrier.forEach(r => r.end());
  server.closeAllConnections(); server.close();
  child.kill();
  await Promise.race([new Promise(r => child.once('exit', r)), delay(2000)]);
  if (path.dirname(profile) === tmpdir() && path.basename(profile).startsWith('hyper-vault-test-')) {
    await rm(profile, { recursive: true, force: true, maxRetries: 6, retryDelay: 200 });
  }
}
