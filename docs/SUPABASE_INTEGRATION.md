# Supabase Integration

This document separates the observed client behavior from the server controls that must exist. The repository currently does not contain reproducible Supabase migrations.

## Client configuration

The Flutter app loads:

- SUPABASE_URL
- SUPABASE_ANON_KEY

from the root .env file through flutter_dotenv.

Rules:

- Commit only .env.example with placeholders.
- Never use SUPABASE_SERVICE_ROLE_KEY in a client application.
- Treat the anon key as public client configuration, while still avoiding accidental mixing of test and production projects.
- Use separate Supabase projects for development, test, staging, and production.
- Record redirect URLs and platform bundle IDs per environment.

The current pubspec bundles .env as an asset. A future configuration ADR should decide whether to keep that pattern or move to a reproducible build-time configuration strategy.

## Authentication operations

The client implements:

- sign up with email, password, and optional name metadata;
- sign in with email and password;
- auth-state stream mapping to UserEntity;
- password-recovery email request;
- password update for an authenticated recovery session;
- sign out.

Current product behavior requires an authenticated user to enter the main application.

## Password recovery

The mobile route /update-password exists, but platform deep links and reset redirect behavior are incomplete.

The reset-password-web page also handles Supabase PASSWORD_RECOVERY sessions. It is not deployable as committed because:

- script.js contains empty URL and anon-key values;
- Compose passes build arguments;
- the Dockerfile declares and consumes no matching arguments;
- the referenced runtime environment-injection concept is not implemented.

Choose one canonical recovery surface, define allowed redirect URLs, and cover expired, reused, malformed, and cross-environment links.

## Current database operations

Table constant: synced_accounts.

### Download

The client selects all rows whose user_id equals the current Supabase user ID. If account_id exists and id does not, it maps account_id to id before AuthenticatorAccount.fromJson.

### Upload

The client:

1. deletes every row whose user_id matches the current user;
2. converts each AuthenticatorAccount to JSON;
3. renames id to account_id;
4. adds user_id;
5. inserts the complete list.

### Status

- hasRemoteData selects id and limits to one row.
- last-upload time selects the newest updated_at.

See DATA_MODELS.md for the observed key mismatch and PROJECT_STATUS.md for risks.

## Required RLS behavior

RLS must be enabled on every user-owned table. For synced_accounts, each operation must enforce:

    auth.uid() = user_id

Required policy coverage:

| Operation | USING | WITH CHECK |
|---|---|---|
| SELECT | auth.uid() = user_id | Not applicable |
| INSERT | Not applicable | auth.uid() = user_id |
| UPDATE | auth.uid() = user_id | auth.uid() = user_id |
| DELETE | auth.uid() = user_id | Not applicable |

These statements are requirements, not proof of deployed configuration. Policies must be tracked in migrations and tested against a local or isolated Supabase environment.

## Required negative tests

- Anonymous clients cannot read or write rows.
- User A cannot select User B rows.
- User A cannot insert a row with User B user_id.
- User A cannot update ownership to User B.
- User A cannot delete User B rows.
- An expired session cannot synchronize.
- Service-role credentials are absent from distributed artifacts.

## Target contract

Do not stabilize the current plaintext row contract as the long-term design. The target contract should use:

- a stable record or snapshot ID;
- user_id ownership;
- a format_version;
- encrypted authenticated payload;
- non-secret version or concurrency metadata;
- created_at and updated_at managed consistently;
- atomic snapshot publication or per-record optimistic concurrency;
- migration state for legacy plaintext rows.

The exact schema requires an accepted ADR and must align with E2EE_DESIGN.md.

## Environment checklist

For each environment, document outside the repository secrets:

- project reference and region;
- allowed redirect URLs;
- email verification and recovery templates;
- SMTP configuration ownership;
- rate limits and abuse controls;
- schema migration version;
- RLS verification result;
- backup and restore policy;
- log retention and access;
- key-management and incident owner.

Do not place actual project URLs or keys in this document.

## Failure behavior

The client must distinguish:

- unauthenticated or expired session;
- authorization denied;
- validation failure;
- network unavailable;
- server conflict;
- schema incompatibility;
- partial or interrupted upload;
- encrypted payload version unsupported.

Do not convert a partial merge into success or retry a destructive operation without idempotency.
