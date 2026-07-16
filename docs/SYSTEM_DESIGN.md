# System Design

This document describes the system that exists in the repository. Proposed encryption and future behavior are documented separately and are not treated as implemented.

## System context

Hyper Authenticator is a Flutter client with two persistence boundaries:

- local device storage for authenticator accounts and preferences;
- Supabase Auth and PostgreSQL for user sessions and optional manual synchronization.

The current product requires Supabase authentication before the authenticator UI can be used.

~~~mermaid
flowchart LR
    User["User"] --> App["Flutter application"]
    App --> DeviceAuth["OS biometric / device credential"]
    App --> SecureStorage["FlutterSecureStorage"]
    App --> Preferences["SharedPreferences"]
    App --> SupabaseAuth["Supabase Auth"]
    App --> SupabaseDB["Supabase synced_accounts"]
    Recovery["Static recovery web page"] --> SupabaseAuth
~~~

## Bootstrap

The runtime startup order is:

1. Flutter bindings initialize.
2. The root .env asset is loaded.
3. Injectable/GetIt registrations and SharedPreferences pre-resolution run.
4. AppConfig reads SUPABASE_URL and SUPABASE_ANON_KEY.
5. Supabase initializes.
6. ThemeProvider, AuthBloc, LocalAuthBloc, AccountsBloc, and SettingsBloc are provided.
7. AuthBloc checks the current Supabase user.
8. LocalAuthBloc checks whether the configured device lock is required.
9. GoRouter selects login, lock, or the main navigation shell.

Any missing or empty Supabase configuration stops normal bootstrap and shows an initialization error screen.

## Navigation

| Route | Purpose | Access |
|---|---|---|
| /login | Sign in | Public |
| /register | Register | Public |
| /forgot-password | Request recovery email | Public |
| /update-password | Set a new password | Route exists but recovery/deep-link flow is incomplete |
| / | Accounts and Settings tabs | Supabase-authenticated |
| /add-account | Add TOTP account | Supabase-authenticated |
| /edit-account | Edit an account passed through route state | Supabase-authenticated |
| /lock-screen | Device credential challenge | Authenticated and lock required |

The router refreshes from AuthBloc and LocalAuthBloc streams. Older documentation that describes Supabase authentication as optional is not correct for the current router.

## Flutter architecture

Code is organized by feature:

    lib/
      core/
      features/
        auth/
        authenticator/
        main_navigation/
        settings/
        sync/

Most features use three layers:

- Presentation: pages, widgets, events, states, and BLoCs.
- Domain: entities, repository contracts, and use cases.
- Data: Supabase and local-storage implementations.

GetIt and Injectable construct dependencies. Theme state uses Provider. Results commonly use fpdart Either values to translate failures without throwing across the domain boundary.

### Ownership caveat

AccountsBloc is registered as a factory. The app-level provider owns one instance, while a factory-created SyncBloc resolves another AccountsBloc. Both can reach the same storage repository, but they do not share UI state. Cross-feature work must use an explicitly shared instance or a repository-level orchestration model.

## Authenticator account flow

### Import

1. AddAccountPage accepts manual fields, a camera barcode, or an image.
2. QR input must use the otpauth scheme and totp host.
3. The page parses issuer, label, secret, algorithm, digits, and period.
4. AccountsBloc calls AddAccount.
5. AuthenticatorRepository writes through AuthenticatorLocalDataSource.
6. The data source assigns a UUID and writes JSON to secure storage.
7. The account UUID is added to a secure-storage index.

Known gap: when assigning a UUID, the active implementation rebuilds the entity without copying algorithm, digits, and period. Non-default input can silently become SHA1, 6 digits, and 30 seconds.

### Read and code generation

1. AccountsBloc reads the account index and each JSON record.
2. AccountsPage invokes GenerateTotpCode for each account.
3. The otp package calculates a code from the local clock and stored parameters.
4. The UI refreshes each second and copies the current code on tap.

Known gap: the visual countdown and regeneration trigger are based on a fixed 30-second cycle even when an account has a different period.

### Update and delete

Update overwrites the JSON record for the same ID. Delete removes the record and then removes the ID from the index. There is no transactional boundary between record and index writes, so recovery behavior for partial failures should be tested.

## Device lock

The biometric_enabled preference is stored in SharedPreferences.

- When disabled or unsupported, LocalAuthBloc emits success and the app proceeds.
- When enabled and supported, the router moves to the lock screen.
- local_auth.authenticate accepts OS biometrics or the configured device credential because biometricOnly is not enabled.
- On pause or detach, app lifecycle handling resets the auth state.
- On resume, the app requests another check.

This is an app gate, not cryptographic protection for individual secure-storage records. Error states require fail-closed routing before production.

## Supabase authentication

AuthRemoteDataSource wraps:

- signInWithPassword;
- signUp with optional name metadata;
- resetPasswordForEmail;
- updateUser for password changes;
- signOut;
- the auth-state stream.

Remember Me stores only the email and checkbox state in SharedPreferences. It does not intentionally persist the password.

Current sign-out handling also deletes all FlutterSecureStorage entries. Because authenticator accounts use the same storage instance, sign-out removes local accounts.

## Synchronization

Synchronization is manual. Enabling sync stores only a SharedPreferences flag.

### Merge path

1. Download every remote account for the current user.
2. Read local accounts.
3. Build identity keys from lowercase issuer and accountName.
4. Add remote accounts whose key is not present locally.
5. Skip existing keys without field comparison or conflict resolution.
6. Read the merged local snapshot.
7. Upload the entire snapshot.

### Overwrite path

1. Take the current UI account list.
2. Delete every remote row for the current user.
3. Insert the provided snapshot.

### Current properties

- Secrets are uploaded as readable JSON fields.
- Upload is not atomic.
- There are no tombstones or deletion propagation rules.
- There is no version vector, updated-at comparison, or multi-device conflict policy.
- The server schema and RLS are not reproduced by tracked migrations.
- Last sync time is inferred from the newest remote updated_at.

See SECURITY.md, SUPABASE_INTEGRATION.md, and E2EE_DESIGN.md.

## Password-recovery web page

reset-password-web is a static HTML, CSS, and JavaScript page that:

1. receives a Supabase recovery session;
2. validates a new password and confirmation;
3. calls Supabase auth.updateUser.

The current container configuration is incomplete: Compose passes build arguments, the Dockerfile does not consume them, and script.js contains empty configuration constants.

## Platform posture

| Platform | Runner | Release posture |
|---|---|---|
| Android | Present | Primary target; permissions and release signing need hardening |
| iOS | Present | Primary target; camera and Face ID descriptions exist; deep links need work |
| macOS | Present | Sandbox entitlements need network/client and plugin verification |
| Web | Present | Metadata is partly template; plugin and dart:io compatibility need verification |
| Windows | Present | Runner only; full feature validation required |
| Linux | Present | Runner only; not an advertised or verified target |

No platform is considered supported until the documented release gate passes on that platform.

## Error handling

Repositories generally convert storage, authentication, and server exceptions into Failure values. BLoCs map those failures into state. Remaining issues include:

- broad catches that lose diagnostic structure;
- production print and debugPrint calls;
- success states emitted after partial sync failure;
- local-auth error routing;
- no telemetry policy or redaction layer.

## Change impact map

- New persisted field: update entity JSON, local round-trip tests, remote contract, migration plan, and DATA_MODELS.md.
- New route or auth rule: update router tests and this document.
- New sync behavior: update conflict semantics, SECURITY.md, SUPABASE_INTEGRATION.md, and destructive-operation tests.
- New plugin or platform: update entitlements/permissions, dependency policy, and DEPLOYMENT.md.
- New encryption behavior: add an ADR, format version, migration, recovery path, and E2EE tests.
