# Security Model

## Current posture

The project must be treated as alpha software. Local storage uses a secure-storage abstraction, but the complete system does not yet provide a production-safe backup or synchronization boundary.

The most important fact is simple: current cloud sync uploads readable TOTP secrets.

## Assets

| Asset | Impact if compromised |
|---|---|
| TOTP secretKey | Attacker can generate the second authentication factor |
| Complete otpauth URI | Equivalent to disclosure of the embedded secret |
| Supabase session | Attacker may access or modify the user cloud snapshot |
| User email and name | Privacy and phishing impact |
| Local account labels | Privacy and account-discovery impact |
| Future encryption key or recovery code | Decrypts or recovers synchronized secrets |

## Trust boundaries

- Flutter process to FlutterSecureStorage.
- Flutter process to SharedPreferences.
- Flutter process to OS local authentication.
- Flutter process to Supabase over the network.
- Supabase Auth to PostgreSQL RLS.
- Password-recovery browser page to Supabase.
- Build environment to bundled client configuration.

Client-side user_id filters are not an authorization boundary. Deployed RLS policies are.

## Implemented controls

- TOTP account JSON is stored through FlutterSecureStorage.
- App locking delegates verification to local_auth and the OS.
- Supabase Auth owns password verification and sessions.
- Repository boundaries convert many infrastructure exceptions to typed failures.
- .env is ignored by Git.
- The client uses an anon key rather than requiring a server key.

These controls do not make plaintext cloud secrets end-to-end encrypted.

## Confirmed release blockers

### Plaintext synchronization

AuthenticatorAccount.toJson includes secretKey. The sync data source inserts that map into Supabase. No encryption, authentication tag, key derivation, key wrapping, or versioned envelope runs in the active path.

Required before production cloud sync:

- accepted E2EE ADR;
- versioned encrypted payload;
- authenticated encryption;
- multi-device key bootstrap;
- recovery design;
- migration from any plaintext rows;
- redacted logs and fixtures;
- cryptographic and integration tests.

### Destructive and non-atomic upload

Upload deletes all user rows, then inserts the replacement list. A failure after delete can erase the cloud copy.

Required:

- database transaction or versioned snapshot commit;
- optimistic concurrency or compare-and-swap;
- idempotent retry;
- server-side validation;
- recovery from interrupted writes;
- explicit destructive confirmation and audit-safe UI.

### Logout data deletion

AuthBloc signs out and then calls deleteAll on the shared secure-storage namespace. This removes local authenticator accounts without a data-specific warning.

Required:

- separate session and account storage namespaces;
- explicit product decision for local data ownership;
- backup/export or recovery behavior;
- regression tests;
- warning text if deletion remains intentional.

### Secret-bearing logs

QR handling currently prints the complete scanned value. A valid otpauth URI contains the secret.

Required:

- remove credential-bearing logs;
- central redaction helpers;
- static review for secretKey, otpauth, token, password, key, salt, and recovery material;
- sanitized error reporting policy.

### Authorization reproducibility

RLS guidance exists, but no tracked migration proves that policies are enabled.

Required:

- version-controlled schema and policies;
- per-user SELECT, INSERT, UPDATE, and DELETE tests;
- negative cross-user tests;
- no service-role credentials in clients.

### App-lock failure behavior

LocalAuthError is not an explicit router deny condition. When a lock is configured, errors must fail closed unless a deliberate recovery policy says otherwise.

## Threat scenarios

| Scenario | Current exposure | Required response |
|---|---|---|
| Supabase database leak | Synced TOTP secrets readable | E2EE and plaintext migration |
| Malicious or mistaken backend operator | Synced secrets readable | Backend-blind ciphertext |
| Network interruption during upload | Cloud snapshot can be deleted | Atomic commit and retry |
| Two devices sync concurrently | Last writer can lose data | Version/conflict protocol |
| Device logs collected | QR secret may appear | Remove and redact logs |
| User signs out before sync | Local accounts are deleted | Safe ownership and warning |
| RLS missing or incorrect | Cross-user data access possible | Tracked policies and negative tests |
| Local-auth plugin error | Possible lock bypass | Fail-closed routing |

## Secure coding rules

- Treat secretKey and otpauth URIs as credentials.
- Never put real credentials in examples, screenshots, issue text, test fixtures, or analytics.
- Do not include service-role keys in Flutter or static web builds.
- Avoid logging raw exceptions from auth or storage when they may contain identifiers or tokens.
- Validate imported algorithms, digits, periods, labels, and Base32 input before persistence.
- Use constant-time or library-provided cryptographic operations; do not implement primitives.
- Version all encrypted and remotely persisted formats.
- Keep destructive operations recoverable and observable.

## Security verification gate

A production release handling real secrets requires:

- threat model reviewed;
- all blockers above resolved or explicitly accepted by the owner;
- unit tests for validation and serialization;
- storage recovery tests;
- cross-user RLS integration tests;
- concurrency and interrupted-sync tests;
- mobile lock lifecycle tests;
- dependency and platform security review;
- privacy policy matched to actual production behavior;
- incident and key-compromise response documented.

## Reporting

Do not open a public issue containing a real secret, token, user email, or production URL. Use a private channel selected by the project owner and provide sanitized reproduction steps.
