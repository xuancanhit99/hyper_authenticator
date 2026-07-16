# Roadmap

This is a risk-first remediation roadmap, not a delivery commitment.

## Phase 0 — Establish a trustworthy baseline

- Add a safe development .env workflow that allows tests to build.
- Replace the commented template with real tests.
- Fix existing analyzer warnings and deprecated API usage without behavior churn.
- Add CI with pinned Flutter.
- Add explicit license and consistent product naming.
- Add version-controlled Supabase schema and RLS migrations.

Exit criteria: quick and full harness gates run deterministically in CI.

## Phase 1 — Protect local correctness

- Preserve algorithm, digits, and period during create and sync restore.
- Make countdown period-aware.
- Validate Base32, algorithm, digits, and period at a domain boundary.
- Remove secret-bearing logs.
- Define secure-storage index recovery.
- Separate authentication/session storage from authenticator storage.
- Decide and implement logout/account-switch data ownership.
- Make app-lock errors fail closed.

Exit criteria: local TOTP and lock flows have unit, BLoC, widget, and device integration coverage.

## Phase 2 — Redesign synchronization

- Accept ADRs for identity, deletion, conflicts, concurrency, and atomic publication.
- Replace delete-then-insert with an atomic, idempotent protocol.
- Use one explicit account-state owner.
- Add tombstones or a documented snapshot revision model.
- Add interrupted-write, retry, and two-device tests.

Exit criteria: no simulated network or concurrency failure loses the last valid snapshot.

## Phase 3 — Implement E2EE

- Accept key hierarchy and recovery ADR.
- Implement versioned authenticated encryption.
- Add multi-device onboarding and recovery.
- Migrate plaintext rows safely.
- Remove plaintext fields and verify no secret reaches remote logs or rows.

Exit criteria: backend-blind secret storage is demonstrated by tests and review.

## Phase 4 — Complete auth and product flows

- Decide whether offline-only use is supported.
- Choose one password-recovery surface.
- Complete deep links and recovery tests.
- Add user-facing data export, deletion, and retention behavior.
- Add localization and accessibility baseline.

Exit criteria: product behavior, privacy policy, and store declarations match.

## Phase 5 — Platform release hardening

- Android signing, permissions, backup, and Play checks.
- iOS signing, Keychain, deep links, and TestFlight checks.
- macOS entitlements and notarization.
- Explicit decision for Web, Windows, and Linux support.
- Release provenance, rollback, and incident procedures.

Exit criteria: DEPLOYMENT.md gates pass for each advertised platform.

## Work selection rule

Do not add convenience features ahead of unresolved credential disclosure or data-loss blockers unless the owner explicitly accepts the risk. Each roadmap item should use docs/tasks/TEMPLATE.md and record verification evidence.
