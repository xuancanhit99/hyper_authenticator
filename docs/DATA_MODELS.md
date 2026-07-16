# Data Models and Storage Contracts

This document describes the shapes implemented in source. Proposed encrypted formats are defined in E2EE_DESIGN.md.

## AuthenticatorAccount

Source: lib/features/authenticator/domain/entities/authenticator_account.dart.

| Field | Dart type | Nullable | Default | Sensitive |
|---|---|---:|---|---:|
| id | String | No | None | No |
| issuer | String | No | None | Potentially |
| accountName | String | No | None | Yes |
| secretKey | String | No | None | Critical credential |
| algorithm | String | No | SHA1 | No |
| digits | int | No | 6 | No |
| period | int | No | 30 | No |

The active model does not contain createdAt, updatedAt, orderIndex, iconPath, counter, tags, or a record version.

### JSON contract

The active toJson method writes:

~~~json
{
  "id": "account-uuid",
  "issuer": "Example",
  "accountName": "user@example.invalid",
  "secretKey": "REDACTED",
  "algorithm": "SHA1",
  "digits": 6,
  "period": 30
}
~~~

Keys use camelCase. fromJson requires id, issuer, accountName, and secretKey. It defaults missing algorithm, digits, and period.

### Required invariants

- id is stable and unique.
- secretKey is a valid Base32 secret accepted by the OTP library.
- algorithm is one of SHA1, SHA256, or SHA512.
- digits is supported by the product contract; current UI validation expects 6 through 8.
- period is positive.
- Every field round-trips through local and remote storage without silent replacement.
- Logs and test reports must redact secretKey.

The current implementation violates the round-trip invariant when a new UUID is assigned. See PROJECT_STATUS.md.

## Local secure-storage layout

Source: lib/features/authenticator/data/datasources/authenticator_local_data_source.dart.

| Storage key | Value |
|---|---|
| authenticator_account_index | JSON array of account IDs |
| each account ID | AuthenticatorAccount JSON |

Create writes the record and then updates the index. Delete removes the record and then updates the index. These multi-step operations are not transactional.

Recovery behavior must be defined for:

- index contains an ID whose record is missing;
- record exists but index update failed;
- malformed JSON;
- duplicate IDs;
- secure-storage read or write failure.

## UserEntity

Source: lib/features/auth/domain/entities/user_entity.dart.

| Field | Dart type | Nullable | Source |
|---|---|---:|---|
| id | String | No | Supabase User.id |
| email | String | Yes | Supabase User.email |
| name | String | Yes | Supabase userMetadata name |

No password or session token is part of UserEntity.

## SharedPreferences keys

The project currently uses string constants in multiple features rather than one central registry.

| Key | Meaning | Sensitive |
|---|---|---:|
| biometric_enabled | Require OS device authentication | No |
| sync_enabled | Display and allow manual sync controls | No |
| remembered_email | Login form convenience | Personal data |
| remember_me_state | Remember Me checkbox | No |
| theme_mode | Theme selection | No |

Exact theme key naming must be checked in ThemeProvider before migration. Preference changes need compatibility behavior for existing installations.

## Observed Supabase row contract

Source: lib/features/sync/data/datasources/supabase_sync_remote_data_source_impl.dart.

The client currently writes a map based on AuthenticatorAccount JSON, then:

- renames id to account_id;
- adds user_id;
- inserts issuer, accountName, secretKey, algorithm, digits, and period.

The client also expects:

- id to exist for hasRemoteData selection;
- updated_at to exist for last-upload time;
- account_id to be mapped back to entity id on download.

This means the observed contract includes both id and account_id semantics and uses camelCase application fields. Older documentation described snake_case fields and does not match the client.

No schema migration is tracked, so the production database shape cannot be reproduced from this repository.

## Remote identity and merge identity

- Remote ownership: user_id.
- Entity identity: id or account_id depending on boundary.
- Current merge identity: lowercase issuer plus lowercase accountName.

Merge identity is not sufficient to distinguish secret rotation, duplicate labels, or two accounts with the same label. It also cannot represent deletions.

## Model change protocol

Any persisted model change must include:

1. A format or schema version.
2. Backward-compatible read behavior.
3. A local migration and rollback or recovery strategy.
4. A remote migration when cloud data changes.
5. Unit tests for old-to-new and new-to-new round trips.
6. Conflict behavior across client versions.
7. Updates to this document, SUPABASE_INTEGRATION.md, and SECURITY.md.

Never use a silent default to hide an unsupported or corrupted persisted value.
