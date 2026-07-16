# Proposed End-to-End Encryption Design

Status: Planned. No part of this document proves that E2EE is implemented.

An architecture decision record must accept the final design before implementation.

## Goal

Supabase and network intermediaries must be unable to read TOTP secrets or account labels from synchronized data. The client must detect ciphertext tampering and prevent accidental cross-user or cross-record decryption.

## Non-goals

- Protecting secrets from a fully compromised unlocked client device.
- Replacing Supabase authentication or RLS.
- Inventing custom cryptographic primitives.
- Claiming recovery is possible without a deliberate key-recovery design.

## Proposed key hierarchy

Use two key levels:

1. A random Data Encryption Key, or DEK, encrypts account payloads.
2. A Key Encryption Key, or KEK, wraps the DEK for each authorized device or recovery method.

Possible KEK sources:

- a key derived from a user-provided master password using a memory-hard KDF;
- a device key protected by secure hardware or platform secure storage;
- a recovery key explicitly exported to the user.

The project must choose how a new device obtains the DEK without giving the backend plaintext key material.

## Proposed payload

A versioned envelope could contain:

~~~json
{
  "formatVersion": 1,
  "recordId": "stable-record-id",
  "cipher": "AES-256-GCM",
  "nonce": "base64",
  "ciphertext": "base64",
  "createdAt": "server-or-client-defined",
  "revision": 1
}
~~~

Plaintext before encryption contains the complete AuthenticatorAccount fields needed for generation. Associated authenticated data should bind at least:

- format version;
- user identity or tenant scope;
- record ID;
- purpose string;
- revision when used by the conflict protocol.

Nonce uniqueness is mandatory for a given key. Use the cryptography library to generate random nonces and authenticated ciphertext.

## Key derivation

If a master password is chosen:

- store a random per-user salt;
- use a reviewed memory-hard KDF available on all supported targets;
- define parameters in the versioned envelope or key metadata;
- enforce rate-limiting only as defense in depth because encrypted blobs permit offline guessing;
- never reuse the Supabase login password implicitly;
- never log the password, derived key, salt, DEK, or recovery data.

If the selected Dart stack cannot provide a suitable cross-platform KDF, resolve that dependency before accepting the design.

## Device onboarding

The final design must specify one or more:

- scan a device-to-device encrypted transfer QR;
- enter a high-entropy recovery key;
- enter a master password that derives a KEK;
- approve a new device from an existing trusted device.

Supabase authentication alone must not reveal the DEK.

## Recovery

Recovery is a product and security decision, not an implementation detail.

Options:

- No recovery: lost key means lost synchronized data.
- User-held recovery key: high entropy, displayed once, never stored in plaintext by the backend.
- Threshold or trusted-device recovery: more complex and requires a separate threat review.

Do not claim password-reset emails can recover E2EE data unless the cryptographic design explicitly enables it.

## Synchronization integration

Upload:

1. Validate and serialize the account.
2. Obtain the DEK in memory.
3. Generate a unique nonce.
4. Encrypt with authenticated associated data.
5. Upload only the versioned envelope and non-secret concurrency metadata.

Download:

1. Validate envelope shape and supported version.
2. Obtain the DEK.
3. Verify and decrypt using associated data.
4. Validate the plaintext model.
5. Persist locally only after successful authentication and validation.

Decryption or validation failure must not overwrite a valid local record.

## Plaintext migration

Before enabling E2EE in production:

1. Inventory legacy plaintext rows.
2. Release a client that can read legacy and encrypted formats but writes only encrypted.
3. Authenticate the user and establish the DEK.
4. Download, validate, encrypt, and atomically migrate the snapshot.
5. Verify encrypted reads.
6. Remove plaintext fields.
7. Track migration completion without exposing secrets.
8. Define rollback before deleting legacy data.

## Test requirements

- Known-answer encryption and decryption tests.
- Random nonce uniqueness test strategy.
- Tampered nonce, ciphertext, tag, associated data, record ID, and version tests.
- Wrong user, wrong device key, and wrong master-password tests.
- Old and future format-version behavior.
- Interrupted migration and retry.
- Multi-device onboarding and revocation.
- Recovery success and failure.
- No plaintext secret in remote request fixtures, logs, crash reports, or database rows.
- Target-platform performance and secure-memory limitations documented.

## Open decisions

- Cipher suite and library.
- KDF and parameters.
- Per-record versus per-snapshot encryption.
- Key rotation and device revocation.
- Recovery model.
- Conflict protocol and associated-data fields.
- Metadata privacy.
- Secure deletion expectations by platform.
- Web support and browser threat model.
