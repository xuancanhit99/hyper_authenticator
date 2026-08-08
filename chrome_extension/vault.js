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

  let keyPromise;
  const vaultKey = async () => {
    if (keyPromise) return keyPromise;
    keyPromise = (async () => {
      const db = await database;
      const readTransaction = db.transaction(keysStore, 'readonly');
      const existing = await requestResult(readTransaction.objectStore(keysStore).get(keyName));
      await transactionDone(readTransaction);
      if (existing instanceof CryptoKey) return existing;

      const generated = await crypto.subtle.generateKey(
        { name: 'AES-GCM', length: 256 },
        false,
        ['encrypt', 'decrypt'],
      );
      const writeTransaction = db.transaction(keysStore, 'readwrite');
      writeTransaction.objectStore(keysStore).put(generated, keyName);
      await transactionDone(writeTransaction);
      return generated;
    })();
    return keyPromise;
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
    const record = await requestResult(transaction.objectStore(recordsStore).get(key));
    await transactionDone(transaction);
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
    transaction.objectStore(recordsStore).put({ iv: iv.buffer, ciphertext }, key);
    await transactionDone(transaction);
  };

  const deleteRecord = async (key) => {
    const db = await database;
    const transaction = db.transaction(recordsStore, 'readwrite');
    transaction.objectStore(recordsStore).delete(key);
    await transactionDone(transaction);
  };

  const readAllJson = async () => {
    const db = await database;
    const transaction = db.transaction(recordsStore, 'readonly');
    const keys = await requestResult(transaction.objectStore(recordsStore).getAllKeys());
    await transactionDone(transaction);
    const values = await Promise.all(keys.map(async (key) => [key, await readRecord(key)]));
    return JSON.stringify(Object.fromEntries(values));
  };

  globalThis.hyperExtensionVault = Object.freeze({
    read: readRecord,
    readAllJson,
    write: writeRecord,
    delete: deleteRecord,
  });
})();
