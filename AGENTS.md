# AI Agent Operating Contract

This file applies to the entire repository. It is the first document an AI coding agent must read.

## Mission

Improve Hyper Authenticator without exposing TOTP secrets, losing user data, or describing planned behavior as implemented behavior.

## Source of truth

Use this precedence when facts disagree:

1. Executed tests and reproducible runtime evidence.
2. Current source code and platform configuration.
3. docs/PROJECT_STATUS.md.
4. Other canonical documents listed in docs/README.md.
5. README translations, comments, and historical notes.

Never copy an old document claim into a new change without checking the code.

## Required startup sequence

1. Run git status --short --branch.
2. Run scripts/agent/context.sh.
3. Read docs/PROJECT_STATUS.md.
4. Read the canonical docs for the affected subsystem.
5. Inspect nearby tests and call sites before editing.
6. State assumptions when evidence is incomplete.

Existing working-tree changes belong to the user. Do not reset, discard, reformat, or overwrite unrelated changes.

## Repository map

- lib/main.dart and lib/app.dart: bootstrap, providers, lifecycle.
- lib/core: routing, configuration, themes, shared failures.
- lib/features/auth: Supabase user authentication.
- lib/features/authenticator: local accounts, TOTP, QR, device lock.
- lib/features/sync: Supabase snapshot synchronization.
- lib/features/settings: biometrics, sync controls, logout.
- assets: fonts, branding, and authenticator logo map.
- android, ios, macos, web, windows, linux: platform runners.
- reset-password-web: separate static Supabase recovery page.
- docs: canonical product and engineering documentation.
- scripts/agent: deterministic orientation and quality-gate helpers.

## Security invariants

- Treat secretKey and every complete otpauth URI as a credential.
- Never print, log, commit, upload to issue text, or place credentials in fixtures.
- Never add a service-role key to a Flutter asset, environment file, or client build.
- Do not claim cloud sync is E2EE until encryption, key recovery, migration, and tests are implemented.
- Destructive operations must be explicit, recoverable where possible, and covered by tests.
- Logout must not silently erase authenticator data.
- Local-auth errors must not accidentally bypass a configured lock.
- Server authorization requires deployed RLS policies; a client-side user_id filter is not authorization.

## Current high-risk areas

Read docs/PROJECT_STATUS.md before touching these:

- plaintext cloud secrets;
- delete-then-insert cloud upload;
- local data deletion on logout;
- loss of non-default TOTP parameters during save;
- incomplete password-recovery deep links;
- SyncBloc and UI AccountsBloc instance ownership;
- missing automated tests and CI;
- incomplete platform permissions, entitlements, and release signing.

## Architecture rules

- UI dispatches events and renders states; it must not own persistence logic.
- Domain entities and use cases must not depend on Flutter widgets.
- Data sources own storage and network mechanics.
- Repositories translate exceptions into typed failures.
- Prefer one BLoC owner per stateful resource. Pass an existing instance when cross-feature coordination is required.
- Persisted fields must round-trip without silent defaults.
- Any remote-schema change requires a migration plan, compatibility notes, and contract tests.
- Generated injection_container.config.dart must match annotations and must not be hand-edited.

## Change discipline

- Keep scope narrow and reversible.
- Diagnose before fixing.
- For a bug, add a regression test that fails for the original behavior.
- For security or storage changes, document threat, migration, rollback, and failure behavior.
- Do not combine formatting churn with behavior changes.
- Do not edit generated platform files unless the change requires it.
- Use docs/tasks/TEMPLATE.md for multi-step work that spans subsystems.
- Use an ADR for long-lived architectural decisions.

## Validation matrix

Documentation only:

    scripts/agent/check.sh docs

Dart logic or UI:

    scripts/agent/check.sh quick

Auth, storage, sync, routing, dependency injection, plugins, or platform files:

    scripts/agent/check.sh full

Also run a target-platform build for platform-specific work. If a baseline failure blocks validation, report the exact existing failure and run every unaffected check.

## Documentation contract

Update documentation in the same change when behavior changes:

- Runtime architecture: docs/SYSTEM_DESIGN.md
- Models or serialization: docs/DATA_MODELS.md
- Security boundary: docs/SECURITY.md
- Supabase contract: docs/SUPABASE_INTEGRATION.md
- Setup or commands: docs/DEVELOPMENT.md
- Tests or gates: docs/TESTING_STRATEGY.md
- Deployment: docs/DEPLOYMENT.md
- Verified gaps: docs/PROJECT_STATUS.md
- Durable decision: docs/ARCHITECTURAL_DECISIONS.md plus an ADR

Use Implemented, Planned, and Known gap labels. Never use future-tense design text as evidence that code exists.

## Handoff requirements

Every completed task must state:

- outcome;
- files changed;
- behavior and data-contract impact;
- validation commands and results;
- remaining risks or follow-ups;
- whether unrelated working-tree changes were preserved.
