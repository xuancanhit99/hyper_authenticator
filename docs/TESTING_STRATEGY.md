# Testing Strategy

## Current baseline

Automated product tests are not implemented.

- test/widget_test.dart is fully commented.
- No integration_test directory exists.
- Native test targets contain templates only.
- No CI pipeline is tracked.
- flutter test currently stops when .env is absent because .env is declared as an asset.
- Static analysis baseline on July 17, 2026: 0 errors, 29 warnings, 72 info diagnostics.

This section must remain until tests and CI replace the baseline.

## Quality gates

Documentation:

    scripts/agent/check.sh docs

Fast Dart and Flutter gate:

    scripts/agent/check.sh quick

Full gate:

    scripts/agent/check.sh full

The harness is intentionally strict. A known baseline failure must be reported, not hidden. When one check is blocked, run every unaffected check.

## Test layers

### Unit tests

Highest priority:

- RFC 6238 and package known-answer TOTP cases.
- algorithm, digits, and period validation.
- AuthenticatorAccount JSON round trip.
- local storage create/read/update/delete and index recovery.
- repository exception-to-failure mapping.
- merge identity and conflict behavior.
- encrypted envelope and migration once E2EE exists.

### BLoC tests

Use bloc_test or an equivalent package after adding it to dev_dependencies.

Cover:

- AuthBloc sign-in, sign-up, recovery, sign-out, and safe data ownership.
- AccountsBloc load, add, update, delete, merge, and partial failure.
- LocalAuthBloc lifecycle, cancellation, unsupported devices, and fail-closed errors.
- SyncBloc disabled, merge, overwrite, network failure, concurrency conflict, and retries.
- SettingsBloc preference persistence.

### Widget tests

Cover:

- login and registration validation;
- add-account manual and QR parse feedback;
- account list code formatting and copy behavior;
- destructive delete and logout warnings;
- lock-screen retry and error behavior;
- sync option descriptions and disabled states;
- theme changes.

All plugin boundaries should be replaceable with fakes.

### Integration tests

Critical journeys:

1. Sign in and load existing local accounts.
2. Add a standard TOTP account and verify a known code.
3. Add SHA256, 8-digit, non-30-second data and verify round trip.
4. Background, resume, and unlock a configured app.
5. Sign out without unintended local data loss.
6. Download and merge without overwriting a conflict.
7. Interrupted upload without losing the last valid cloud snapshot.
8. User A cannot access User B data through Supabase RLS.
9. Password-recovery link success, expiration, and reuse.

Use isolated synthetic environments and never production credentials.

### Platform verification

For each supported platform:

- clean install and upgrade;
- secure-storage persistence and deletion semantics;
- biometric or device-credential availability and cancellation;
- camera and gallery permissions;
- network access in a release build;
- background and resume behavior;
- deep links;
- release signing and sandbox entitlements.

## Fixtures

- Use example.invalid addresses.
- Use synthetic RFC test vectors, never a personal account.
- Mark every secret-looking fixture as TEST_ONLY.
- Do not snapshot real Supabase responses or sessions.
- Redact otpauth secret values from failure output.

## Coverage policy

Coverage percentage is secondary to risk coverage. However, before beta:

- every domain use case must have success and failure tests;
- every persisted model must have round-trip and migration tests;
- every destructive path must have interruption and rollback tests;
- auth, lock, sync, and recovery must have integration coverage;
- security regressions must have a permanent test.

Do not exclude security-critical files merely to raise the percentage.

## CI target

A future pull-request pipeline should run:

1. dependency resolution with a pinned Flutter version;
2. generated-code drift check;
3. formatting check;
4. static analysis with no new diagnostics;
5. unit and widget tests;
6. documentation harness;
7. secret scanning;
8. at least Android debug build;
9. scheduled or protected platform and Supabase integration suites.

CI must receive only environment-scoped public client configuration. Production credentials are not allowed.

## Definition of done

A behavior change is complete only when:

- acceptance criteria are observable;
- regression coverage exists;
- relevant quality gates pass or existing blockers are reported exactly;
- data and security failure behavior is tested;
- affected canonical docs are updated;
- platform-specific validation is recorded when applicable.
