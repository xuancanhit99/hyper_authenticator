# Project Status

Verified on July 17, 2026 against the local repository whose base HEAD was 6bf2598. The worktree already contained unrelated iOS, macOS, and pubspec.lock changes; those are not evaluated here.

## Executive status

Hyper Authenticator is an alpha-quality Flutter application. The local TOTP experience is substantially implemented. Authentication and manual Supabase synchronization also exist, but security, data-loss, testing, and release configuration gaps prevent production use with real authenticator secrets.

## Verified toolchain

- Flutter 3.44.6 stable.
- Dart 3.12.2.
- pubspec constraint: Dart 3.7.2 or compatible.
- Application version: 1.0.0+9.

## Capability matrix

| Capability | Status | Notes |
|---|---|---|
| Supabase email/password sign-in | Implemented | Required by router, despite older docs describing it as optional |
| Registration | Implemented | Name stored in Supabase user metadata |
| Password recovery email | Partial | Mobile deep link and auxiliary web configuration are incomplete |
| Local TOTP storage | Implemented | FlutterSecureStorage with an index key and per-account JSON |
| TOTP generation | Implemented with defects | Domain accepts algorithm, digits, period; new-account persistence can drop non-default values |
| Camera QR import | Implemented | otpauth TOTP only |
| Gallery QR import | Implemented | Uses MobileScanner image analysis |
| Manual import | Implemented | Defaults to SHA1, 6 digits, 30 seconds |
| Search, copy, edit, delete, QR export | Implemented | UI is English-only |
| Device-credential lock | Implemented with gaps | Uses OS biometric or device credential, not an app-specific PIN |
| Theme selection | Implemented | SharedPreferences |
| Cloud merge | Implemented with data-loss risk | Add-only merge, then destructive snapshot upload |
| Cloud overwrite | Implemented with data-loss risk | Delete-all then insert-all |
| Client-side E2EE | Planned | No encryption or decryption in the active sync path |
| Automated tests | Not implemented | Only a fully commented Flutter template test exists |
| CI | Not implemented | No tracked pipeline |
| Reproducible Supabase schema | Not implemented | No migrations or generated schema contract |
| Production release configuration | Not ready | Signing, permissions, entitlements, privacy, and platform verification remain |

## Release blockers

### Security and data protection

1. TOTP secretKey is serialized and uploaded to Supabase without client-side encryption.
2. Complete otpauth URIs, including secrets, can be written to debug output during QR scanning.
3. Deployed RLS cannot be verified because no migration or policy files are tracked.
4. Local-auth error states are not treated as an explicit deny state by router logic.
5. The privacy policy and production data flow must remain aligned.

### Data integrity

1. Cloud upload deletes all remote rows before inserting the replacement snapshot. The operation is not atomic.
2. Merge keys only on lowercase issuer and accountName. It does not update conflicts or represent deletions.
3. Partial merge failures are logged but can still proceed to upload.
4. New local account persistence rebuilds the entity without algorithm, digits, and period, silently restoring defaults.
5. The account-list countdown is hard-coded to a 30-second display cycle.
6. Signing out calls deleteAll on the shared secure-storage namespace and removes local authenticator accounts without a specific warning.
7. SyncBloc resolves a different factory AccountsBloc from the one displayed by the UI, which can leave UI state stale.

### Product and operations

1. Supabase configuration and sign-in are mandatory at startup; offline-only use is not available.
2. Password-recovery deep links are not fully configured.
3. reset-password-web passes unused Docker build arguments while script.js contains empty Supabase configuration.
4. Android release networking and macOS sandbox entitlements require verification and correction.
5. Product naming is inconsistent across Hyper Authenticator, HyperZ, and template metadata.
6. No explicit license file is tracked.

## Quality baseline

The following was observed before the documentation rewrite:

    dart analyze --format=machine

Result: 0 errors, 29 warnings, 72 info diagnostics.

    dart format --output=none --set-exit-if-changed lib test tool

Result: formatting drift reported in 7 existing Dart files.

    flutter test

Result: asset-bundle construction failed because the ignored .env file did not exist.

Test inventory:

- test/widget_test.dart is entirely commented out.
- No integration_test directory.
- iOS and macOS native test targets are templates without product tests.
- No CI workflow is tracked.

## Evidence locations

- Bootstrap and mandatory Supabase initialization: lib/main.dart.
- Mandatory auth redirect and local lock: lib/core/router/app_router.dart.
- Local account persistence: lib/features/authenticator/data/datasources/authenticator_local_data_source.dart.
- TOTP generation: lib/features/authenticator/domain/usecases/generate_totp_code.dart.
- Cloud snapshot upload: lib/features/sync/data/datasources/supabase_sync_remote_data_source_impl.dart.
- Merge behavior: lib/features/authenticator/presentation/bloc/accounts_bloc.dart.
- Logout storage clearing: lib/features/auth/presentation/bloc/auth_bloc.dart.
- Recovery web page: reset-password-web.

## Updating this document

Change a status only after code and verification agree. Include the command or test that establishes the new baseline. Move resolved defects to release notes or an ADR instead of keeping stale warnings here.
