# End-to-End Encryption (E2EE) Design for Cloud Synchronization

This document details the proposed design for implementing client-side End-to-End Encryption (E2EE) for the cloud synchronization feature in Hyper Authenticator. The goal is to ensure that sensitive user data, particularly TOTP secrets, are encrypted on the client device before being uploaded to the Supabase backend, making them unreadable by the server or any intermediaries.

## 1. Goals

*   **Confidentiality:** Only the user should be able to decrypt and access their synchronized TOTP secrets. The backend provider (Supabase) should not have access to the plaintext secrets.
*   **Integrity:** Ensure that the encrypted data stored on the backend has not been tampered with.
*   **Usability:** The encryption/decryption process should be largely transparent to the user during normal operation. Key management should be as secure and user-friendly as possible.

## 2. Cryptographic Primitives

*   **Symmetric Encryption Algorithm:** AES-GCM (Advanced Encryption Standard with Galois/Counter Mode) using a 256-bit key.
    *   **Reasoning:** AES is a widely adopted, secure, and performant standard. GCM mode provides both confidentiality (encryption) and integrity (authentication tag), protecting against tampering.
*   **Key Derivation Function (KDF):** Argon2id (preferred) or PBKDF2-HMAC-SHA256.
    *   **Reasoning:** Used if deriving the encryption key from a user-defined master password. These KDFs are designed to be computationally intensive, making brute-force attacks on the master password much harder. Argon2id is generally considered stronger against various attacks.
*   **Random Number Generation:** Cryptographically secure pseudo-random number generator (CSPRNG) provided by the OS/platform (e.g., via `dart:math`'s `Random.secure()` or the `cryptography` package utilities). Used for generating nonces/IVs and potentially random encryption keys.
*   **Library:** `cryptography` package in Dart/Flutter. Provides implementations for AES-GCM, KDFs, and secure random generation.

## 3. Key Management Strategy

This is the most critical and complex part of E2EE. Two primary approaches are considered:

### Approach A: Key Derived from Master Password

1.  **Setup:**
    *   When enabling sync for the first time (or setting up E2EE), the user is prompted to create a strong **Master Password**. *This password is known only to the user and is NEVER sent to the server.*
    *   A unique, cryptographically secure **salt** (e.g., 16 bytes) is generated for the user and stored alongside their *encrypted* data on Supabase (or potentially in a separate user profile table). The salt is not secret but must be unique per user.
    *   The **Encryption Key (EK)** is derived from the Master Password and the salt using the chosen KDF (Argon2id or PBKDF2). `EK = KDF(MasterPassword, Salt, parameters)`. Parameters (iterations, memory cost, parallelism for Argon2) should be chosen carefully for adequate security.
2.  **Encryption/Decryption:**
    *   The derived EK is used for all AES-GCM encryption/decryption operations for that user's data.
    *   The EK is held in memory only when needed (e.g., during sync, potentially cached briefly after successful login/unlock) and should be cleared as soon as possible. It is **never** stored directly on disk.
3.  **Login/Unlock:**
    *   When the user logs in or unlocks the sync feature, they must provide the Master Password.
    *   The app retrieves the user's salt from Supabase.
    *   It re-derives the EK using the provided password and the salt.
    *   To verify the password is correct *without* decrypting all data, a separate **Verification Value (VV)** can be stored on Supabase. VV = Encrypt(KnownConstant, EK). During login, the app derives EK, decrypts VV, and checks if it matches the KnownConstant.
4.  **Pros:**
    *   Key is not stored directly anywhere, only derived.
    *   Relatively simpler cross-device setup (user just needs to remember the Master Password and enter it on new devices).
5.  **Cons:**
    *   **Password Forgetting:** If the user forgets the Master Password, the EK cannot be derived, and **all encrypted data becomes permanently inaccessible**. Recovery is extremely difficult without compromising security (e.g., pre-generated recovery codes stored securely by the user).
    *   **Password Strength:** Security relies heavily on the strength of the user's chosen Master Password and the KDF parameters.
    *   Requires user interaction (entering password) to unlock sync features.

### Approach B: Randomly Generated Key Stored Securely

1.  **Setup:**
    *   When enabling sync/E2EE, a strong, unique **Encryption Key (EK)** (e.g., 256-bit) is generated using a CSPRNG.
    *   This EK is stored directly in the device's `FlutterSecureStorage`.
2.  **Encryption/Decryption:**
    *   The EK is retrieved from `FlutterSecureStorage` when needed for AES-GCM operations.
3.  **Login/Unlock:**
    *   Access to the EK in `FlutterSecureStorage` might be implicitly protected by device lock (PIN/Biometrics) depending on the platform implementation. No separate Master Password needed for decryption itself.
4.  **Pros:**
    *   No Master Password for the user to forget (related to encryption key).
    *   Key strength is guaranteed by the CSPRNG.
    *   Potentially more seamless user experience (no extra password prompt for decryption if device is unlocked).
5.  **Cons:**
    *   **Key Loss:** If the app is uninstalled, the device is wiped, or `FlutterSecureStorage` data is lost, the EK is gone, and **all encrypted data becomes permanently inaccessible**.
    *   **Cross-Device Setup:** Getting the *same* EK onto a new device securely is challenging. Options:
        *   **Manual Backup/Transfer:** User manually exports the key (e.g., as a QR code or file) and imports it on the new device. Requires careful user action and secure handling of the exported key.
        *   **Cloud Key Sync (Complex & Risky):** Attempting to sync the EK itself via a cloud service introduces significant security risks and complexity (e.g., encrypting the EK with another key derived from user login password - partially defeats the purpose). Generally discouraged unless implemented with extreme care.
        *   **Recovery Codes:** Generate recovery codes during setup that the user stores securely. These codes could potentially be used to re-access/re-encrypt data if the primary key is lost (complex implementation).

**Chosen Approach (Recommendation):** Approach A (Key Derived from Master Password) is often preferred for user-facing E2EE due to the simpler cross-device story, despite the password recovery challenge. Implementing secure recovery codes alongside Approach A is highly recommended.

## 4. Data Structure for Encryption

*   Instead of encrypting each field (`secretKey`, `issuer`, `accountName`) individually, it's generally more efficient and secure to:
    1.  Serialize the sensitive parts of the `AuthenticatorAccount` object (or a dedicated DTO) into a structured format (e.g., JSON string).
    2.  Encrypt this entire serialized string using AES-GCM with the EK.
    3.  Store the resulting ciphertext (and the nonce/IV used for encryption) in a single field (e.g., `encrypted_data`) in the Supabase table (`synced_accounts`).
    4.  Non-sensitive fields needed for querying or sorting (like `id`, `user_id`, `order_index`, `created_at`) can remain unencrypted in separate columns.

*   **Encryption Process:**
    1.  Get EK (derive from Master Password or retrieve from SecureStorage).
    2.  Serialize account data (e.g., `{'secret': '...', 'issuer': '...', 'name': '...'}`).
    3.  Generate a unique, random nonce (IV) for each encryption operation (e.g., 12 bytes for AES-GCM). **Never reuse a nonce with the same key.**
    4.  Encrypt the serialized data using AES-GCM, EK, and the nonce. This produces ciphertext and an authentication tag.
    5.  Store the nonce + ciphertext + tag together (e.g., base64 encoded) in the `encrypted_data` column.

*   **Decryption Process:**
    1.  Get EK.
    2.  Retrieve the stored value (nonce + ciphertext + tag) from `encrypted_data`.
    3.  Extract the nonce.
    4.  Decrypt the ciphertext using AES-GCM, EK, nonce, and the tag. GCM automatically verifies the tag for integrity. If decryption fails or the tag is invalid, the data has been tampered with or the wrong key/nonce was used.
    5.  Deserialize the resulting plaintext back into the account object/DTO.

## 5. Synchronization Flow Integration

*   **Upload:**
    1.  User triggers sync (e.g., manual sync, background sync).
    2.  App prompts for Master Password if EK is not already in memory (Approach A). Derives/Retrieves EK.
    3.  For each local `AuthenticatorAccount` to be synced:
        *   Serialize sensitive fields.
        *   Generate nonce.
        *   Encrypt using EK and nonce.
        *   Prepare `SyncedAccountDto` with `encrypted_data` (containing nonce+ciphertext+tag) and unencrypted fields (`id`, `user_id`, `order_index`, etc.).
    4.  Call `SyncRemoteDataSource.uploadToSupabase` with the list of DTOs.
*   **Download:**
    1.  User triggers sync or logs in on a new device.
    2.  App prompts for Master Password if EK is not already in memory (Approach A). Derives/Retrieves EK.
    3.  Call `SyncRemoteDataSource.downloadFromSupabase`.
    4.  For each received `SyncedAccountDto`:
        *   Extract nonce and ciphertext+tag from `encrypted_data`.
        *   Decrypt using EK and nonce. Verify integrity tag.
        *   Deserialize plaintext into account details.
        *   Create/Update local `AuthenticatorAccount` in `FlutterSecureStorage`.

## 6. Recovery Mechanism (Essential for Approach A)

*   **Concept:** Generate a set of single-use recovery codes (e.g., 12-24 words or alphanumeric codes) when the user sets up E2EE/Master Password.
*   **Storage:** The user **must** store these codes securely offline (print them, save in a password manager). The app/server should **not** store them.
*   **Usage:** If the user forgets the Master Password:
    1.  They initiate a recovery process.
    2.  They enter one of their recovery codes.
    3.  The app/server verifies the code (requires a mechanism to store hashes of recovery codes or a related verification value server-side without storing the codes themselves).
    4.  If valid, allow the user to set a *new* Master Password.
    5.  **Crucially:** All existing data on the server needs to be downloaded, decrypted with the *old* EK (which might be temporarily derived/retrieved using the recovery code mechanism if designed carefully, or this step might be impossible depending on the exact recovery design), and then **re-encrypted** with the *new* EK derived from the new Master Password. This is a complex and potentially slow process.
    6.  Invalidate the used recovery code.

## 7. Future Considerations

*   **Key Rotation:** Periodically rotating the EK could enhance security but adds significant complexity to key management and synchronization.
*   **Algorithm Agility:** Design the storage format (e.g., how nonce/ciphertext/tag are combined) to potentially accommodate different encryption algorithms in the future.