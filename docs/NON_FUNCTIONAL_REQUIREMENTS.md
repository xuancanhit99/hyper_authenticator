# Non-Functional Requirements

Targets marked Proposed are not yet measured or enforced.

## Security

Required:

- No readable TOTP secret leaves the client during production sync.
- No credential appears in logs, analytics, crash reports, screenshots, or fixtures.
- Cross-user Supabase access tests deny every operation.
- Configured app lock fails closed on plugin or routing error.
- No production artifact contains a service-role or server secret.
- All critical and high security findings are resolved before release.

## Correctness and reliability

Required:

- TOTP output matches RFC 6238 or equivalent known-answer vectors for supported algorithms.
- Every account field round-trips through local storage.
- Sync interruption cannot destroy the last valid local or cloud snapshot.
- Merge and deletion semantics are deterministic and documented.
- Retry is idempotent.
- Unsupported schema or encrypted-format versions fail without overwriting valid data.

## Availability

Product decision required: offline-only access versus mandatory Supabase authentication.

If offline core use is accepted, TOTP viewing must remain available without network after local unlock. If mandatory auth remains, the dependency and outage behavior must be stated publicly.

## Performance

Proposed initial targets on a representative mid-range mobile device:

- cached account list visible within 500 ms after the app shell is ready;
- TOTP generation under 10 ms per account at the 95th percentile for 100 accounts;
- account-list scrolling remains responsive with 500 accounts;
- no network or secure-storage loop blocks the UI thread;
- sync progress remains observable and cancellable.

Measure before adopting these as release SLOs.

## Privacy

Required:

- Data inventory matches the privacy policy.
- User-triggered cloud sync is distinguishable from local storage.
- Account deletion and retention behavior is documented.
- Personal data is minimized in logs and support workflows.
- Third-party services and hosted dependencies are disclosed.

## Usability and accessibility

Proposed targets:

- all critical flows usable with screen readers;
- text respects system scaling without clipping;
- actions do not rely on color alone;
- destructive actions explain exact data impact;
- copy feedback does not expose the copied secret;
- localization strategy is defined before adding more hard-coded text.

## Maintainability

Required:

- Canonical docs updated with behavior.
- No generated DI drift.
- New defects receive regression tests.
- Persisted contracts are versioned before incompatible change.
- Architectural changes have ADRs.
- Static-analysis diagnostics do not increase without explicit rationale.

## Portability

A platform is supported only after:

- required plugins are compatible;
- permissions and entitlements are correct;
- secure-storage and local-auth behavior are tested;
- release build, install, upgrade, and rollback pass;
- limitations are documented.

Runner presence alone is not support.

## Observability

Proposed:

- structured event categories with redaction at the boundary;
- no raw auth or sync payloads;
- correlation IDs that cannot reveal user or account identity;
- actionable error classes for auth, storage, network, schema, and crypto;
- opt-in crash reporting with documented retention and provider.

## Recovery

Required before production:

- local storage inconsistency recovery;
- remote snapshot rollback;
- key-loss and E2EE recovery policy;
- account export or backup decision;
- incident response for credential or backend compromise.

## Enforcement

Each requirement must eventually map to one or more:

- automated test;
- CI rule;
- platform release checklist;
- security review;
- operational monitor;
- accepted risk with owner and expiration.
