# Data Models

This document defines the structure of key data models used within the Hyper Authenticator application, including Domain Entities and Data Transfer Objects (DTOs).

## 1. Domain Entities

These represent the core business objects of the application.

### 1.1. `AuthenticatorAccount` (Domain Entity)

Represents a single 2FA account stored by the user.

| Field         | Type     | Description                                      | Nullable | Example                               |
|---------------|----------|--------------------------------------------------|----------|---------------------------------------|
| `id`          | `String` | Unique identifier for the account (e.g., UUID)   | No       | `"a1b2c3d4-..."`                      |
| `secretKey`   | `String` | The Base32 encoded secret key for TOTP generation| No       | `"JBSWY3DPEHPK3PXP"`                  |
| `issuer`      | `String` | The name of the service/issuer (e.g., "Google")  | Yes      | `"Google"`                            |
| `accountName` | `String` | The username or email associated with the account| No       | `"user@example.com"`                  |
| `digits`      | `int`    | Number of digits in the generated TOTP code      | No       | `6`                                   |
| `period`      | `int`    | Time step duration in seconds for TOTP           | No       | `30`                                  |
| `algorithm`   | `String` | Hashing algorithm used (SHA1, SHA256, SHA512)    | No       | `"SHA1"`                              |
| `createdAt`   | `DateTime`| Timestamp when the account was added           | No       | `DateTime.now()`                      |
| `orderIndex`  | `int`    | Used for maintaining user-defined sort order     | No       | `0`                                   |

### 1.2. `UserEntity` (Domain Entity)

Represents an authenticated user of the application (primarily for sync features).

| Field      | Type     | Description                               | Nullable | Example                 |
|------------|----------|-------------------------------------------|----------|-------------------------|
| `id`       | `String` | Unique user ID provided by Supabase Auth  | No       | `"uuid-from-supabase"`  |
| `email`    | `String` | User's email address                      | Yes      | `"user@example.com"`    |
| `createdAt`| `DateTime`| Timestamp of user creation              | Yes      | `DateTime.now()`        |

## 2. Data Transfer Objects (DTOs)

These models are typically used for communication with external services (like Supabase) or for specific data storage formats.

### 2.1. `SyncedAccountDto` (Data Layer Model/DTO)

Represents the structure of an account as stored in/retrieved from the Supabase database for synchronization. This structure might differ slightly from the Domain Entity, especially concerning encryption.

**Note:** The exact structure depends on the implementation details of synchronization, particularly E2EE.

**Example Structure (Pre-E2EE or with server-side handling):**

| Field         | Type     | Description                                       | Nullable | Notes                                     |
|---------------|----------|---------------------------------------------------|----------|-------------------------------------------|
| `id`          | `String` | Primary Key (matches `AuthenticatorAccount.id`)   | No       | UUID                                      |
| `user_id`     | `String` | Foreign Key linking to the Supabase user (`auth.users.id`) | No       | UUID                                      |
| `secret_key`  | `String` | Base32 encoded secret key                         | No       | **Needs E2EE before storing raw**         |
| `issuer`      | `String` | Service/issuer name                               | Yes      |                                           |
| `account_name`| `String` | Username/email                                    | No       |                                           |
| `digits`      | `int`    | Number of TOTP digits                             | No       |                                           |
| `period`      | `int`    | TOTP period in seconds                            | No       |                                           |
| `algorithm`   | `String` | Hashing algorithm                                 | No       |                                           |
| `created_at`  | `timestamp`| Timestamp from `AuthenticatorAccount.createdAt` | No       | Stored as Supabase timestamp type         |
| `order_index` | `int`    | Sort order index                                  | No       |                                           |
| `updated_at`  | `timestamp`| Timestamp of the last modification in Supabase  | No       | Managed by Supabase                       |

**Example Structure (With Client-Side E2EE):**

| Field          | Type     | Description                                       | Nullable | Notes                                     |
|----------------|----------|---------------------------------------------------|----------|-------------------------------------------|
| `id`           | `String` | Primary Key (matches `AuthenticatorAccount.id`)   | No       | UUID                                      |
| `user_id`      | `String` | Foreign Key linking to the Supabase user (`auth.users.id`) | No       | UUID                                      |
| `encrypted_data`| `String` | Encrypted blob containing sensitive fields (secret, issuer, name, etc.) | No | Encrypted using client-side key (AES-GCM) |
| `created_at`   | `timestamp`| Timestamp from `AuthenticatorAccount.createdAt` | No       | Stored as Supabase timestamp type         |
| `order_index`  | `int`    | Sort order index                                  | No       | Stored unencrypted for server-side sorting? (Consider implications) |
| `updated_at`   | `timestamp`| Timestamp of the last modification in Supabase  | No       | Managed by Supabase                       |

*(Mapping logic between `AuthenticatorAccount` and `SyncedAccountDto` resides in the Data Layer, potentially within the Repository implementation or dedicated Mapper classes.)*