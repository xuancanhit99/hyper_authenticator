# Architectural Decisions

This document indexes durable decisions. Detailed new decisions use records in docs/adr.

## Adopted decisions reflected in code

| ID | Decision | Status | Evidence |
|---|---|---|---|
| A-001 | Flutter and Dart for the client | Adopted | pubspec.yaml and platform runners |
| A-002 | Feature-first Presentation, Domain, Data layering | Adopted with inconsistencies | lib/features |
| A-003 | BLoC for feature state and Provider for theme | Adopted | flutter_bloc and ThemeProvider |
| A-004 | GetIt and Injectable for dependency construction | Adopted | injection_container files |
| A-005 | FlutterSecureStorage for authenticator records | Adopted | AuthenticatorLocalDataSource |
| A-006 | SharedPreferences for non-secret preferences | Adopted | theme, biometric, sync, Remember Me |
| A-007 | Supabase for user authentication and remote sync | Adopted | auth and sync data sources |
| A-008 | fpdart Either values at repository/use-case boundaries | Adopted | domain and data layers |
| A-009 | GoRouter redirects from auth and local-lock state | Adopted | AppRouter |

Adopted does not mean flawless. PROJECT_STATUS.md records defects in the current realization.

## Decisions that must be made

| Proposed ID | Decision needed | Why |
|---|---|---|
| P-001 | Is offline-only use supported, or is Supabase auth mandatory? | README history and router behavior disagree |
| P-002 | E2EE key hierarchy, recovery, and encrypted format | Plaintext cloud secrets block release |
| P-003 | Atomic sync and conflict/deletion protocol | Current delete-insert snapshot loses data |
| P-004 | Authenticator data ownership on logout and account switch | Current logout deletes local accounts |
| P-005 | Single AccountsBloc ownership or repository-level orchestration | Sync and UI resolve different instances |
| P-006 | Canonical password-recovery surface | Mobile deep link and web page overlap |
| P-007 | Supported platform matrix | Runners exist beyond verified targets |
| P-008 | Client configuration strategy | .env is ignored but bundled as an asset |
| P-009 | Product name and identifiers | Hyper Authenticator and HyperZ are mixed |
| P-010 | License | No explicit license file is tracked |

## ADR process

Create an ADR when a change:

- modifies a trust boundary or cryptographic design;
- changes a persisted or remote data contract;
- changes supported platforms or backend;
- introduces destructive semantics;
- changes state ownership or the primary architecture pattern;
- selects a dependency with long-lived constraints.

Steps:

1. Copy docs/adr/0000-template.md.
2. Assign the next four-digit number and a short slug.
3. Describe context, decision, alternatives, consequences, migration, rollback, and verification.
4. Mark status Proposed.
5. Obtain owner approval.
6. Change status to Accepted and add the record to this index.
7. Mark superseded records instead of rewriting history.

## Historical rationale

The current choices optimize for a single cross-platform codebase, explicit state transitions, replaceable data sources, and fast backend bootstrap. Their main trade-offs are generated-code maintenance, BLoC boilerplate, platform-plugin differences, dependence on Supabase configuration, and the need for disciplined boundary tests.
