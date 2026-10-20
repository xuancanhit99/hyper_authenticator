// Local-only Manifest V3 vault bridge. It deliberately has no network API,
// logging, or Chrome storage dependency. CryptoKey is structured-cloned into
// IndexedDB with extractable=false, so raw AES key bytes never enter a web
// storage record.
(() => {
  'use strict';

  const databaseName = 'hyper-authenticator-extension-v1';
  const databaseVersion = 1;
  const keysStore = 'keys';
  const recordsStore = 'records';
  const keyName = 'vault-key';
  const aadPrefix = 'hyper-authenticator-extension-v1:';
  const textEncoder = new TextEncoder();
  const textDecoder = new TextDecoder();

  const requestResult = (request) => new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('IndexedDB request failed.'));
  });

  const transactionDone = (transaction) => new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error || new Error('IndexedDB transaction aborted.'));
    transaction.onerror = () => reject(transaction.error || new Error('IndexedDB transaction failed.'));
  });

  const database = new Promise((resolve, reject) => {
    const request = indexedDB.open(databaseName, databaseVersion);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(keysStore)) db.createObjectStore(keysStore);
      if (!db.objectStoreNames.contains(recordsStore)) db.createObjectStore(recordsStore);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error || new Error('Unable to open extension vault.'));
  });

  const vaultKey = async () => {
      // Generate outside IDB, then choose the winner inside a single transaction
      // shared by every extension context. Never replace an existing key.
      const generated = await crypto.subtle.generateKey(
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt'],
      );
      const db = await database;
      const transaction = db.transaction([keysStore, recordsStore], 'readwrite');
      const done = transactionDone(transaction);
      const keys = transaction.objectStore(keysStore);
      const existing = await requestResult(keys.get(keyName));
      if (existing !== undefined) {
        await done;
        if (!(existing instanceof CryptoKey) || existing.extractable ||
            existing.algorithm.name !== 'AES-GCM' || existing.algorithm.length !== 256 ||
            !existing.usages.includes('encrypt') || !existing.usages.includes('decrypt')) {
          throw new Error('Extension vault key is invalid; data preserved.');
        }
        return existing;
      }
      const count = await requestResult(transaction.objectStore(recordsStore).count());
      if (count !== 0) {
        await done;
        throw new Error('Extension vault key is missing; data preserved.');
      }
      keys.add(generated, keyName);
      await done;
      return generated;
  };

  const algorithmFor = (key, iv) => ({
    name: 'AES-GCM',
    iv,
    additionalData: textEncoder.encode(`${aadPrefix}${key}`),
    tagLength: 128,
  });

  const readRecord = async (key) => {
    const db = await database;
    const transaction = db.transaction(recordsStore, 'readonly');
    const done = transactionDone(transaction);
    const record = await requestResult(transaction.objectStore(recordsStore).get(key));
    await done;
    if (record === undefined) return null;
    if (!(record.iv instanceof ArrayBuffer) || !(record.ciphertext instanceof ArrayBuffer)) {
      throw new Error('Chrome Extension vault record is invalid.');
    }
    const plain = await crypto.subtle.decrypt(
      algorithmFor(key, new Uint8Array(record.iv)),
      await vaultKey(),
      record.ciphertext,
    );
    return textDecoder.decode(plain);
  };

  const writeRecord = async (key, value) => {
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ciphertext = await crypto.subtle.encrypt(
      algorithmFor(key, iv),
      await vaultKey(),
      textEncoder.encode(value),
    );
    const db = await database;
    const transaction = db.transaction(recordsStore, 'readwrite');
    const done = transactionDone(transaction);
    transaction.objectStore(recordsStore).put({ iv: iv.buffer, ciphertext }, key);
    await done;
  };

  const deleteRecord = async (key) => {
    const db = await database;
    const transaction = db.transaction(recordsStore, 'readwrite');
    const done = transactionDone(transaction);
    transaction.objectStore(recordsStore).delete(key);
    await done;
  };

  const readAllJson = async () => {
    const db = await database;
    const transaction = db.transaction(recordsStore, 'readonly');
    const done = transactionDone(transaction);
    const store = transaction.objectStore(recordsStore);
    const [keys, records] = await Promise.all([
      requestResult(store.getAllKeys()), requestResult(store.getAll()),
    ]);
    await done;
    const aesKey = await vaultKey();
    const values = await Promise.all(keys.map(async (key, index) => {
      const record = records[index];
      const plain = await crypto.subtle.decrypt(
        algorithmFor(key, new Uint8Array(record.iv)), aesKey, record.ciphertext,
      );
      return [key, textDecoder.decode(plain)];
    }));
    return JSON.stringify(Object.fromEntries(values));
  };

  let nextLock = 0;
  const heldLocks = new Map();
  const beginExclusive = () => new Promise((resolve, reject) => {
    if (!navigator.locks) { reject(new Error('Vault locking is unavailable.')); return; }
    navigator.locks.request('hyper-authenticator-vault-mutation-v3', async () => {
      const token = String(++nextLock);
      await new Promise((release) => { heldLocks.set(token, release); resolve(token); });
      heldLocks.delete(token);
    }).catch(reject);
  });
  const endExclusive = async (token) => {
    const release = heldLocks.get(token);
    if (!release) throw new Error('Vault lock is not held.');
    release();
  };

  globalThis.hyperExtensionVault = Object.freeze({
    read: readRecord,
    readAllJson,
    write: writeRecord,
    delete: deleteRecord,
    beginExclusive,
    endExclusive,
  });
})();
