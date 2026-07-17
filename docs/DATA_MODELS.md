# Mô hình dữ liệu và storage contract

Tài liệu mô tả shape đã triển khai. Encrypted format mục tiêu nằm trong `E2EE_DESIGN.md`.

## AuthenticatorAccount

Source: `lib/features/authenticator/domain/entities/authenticator_account.dart`.

| Field | Kiểu | Nullable | Default | Nhạy cảm |
|---|---|---:|---|---:|
| `id` | String | Không | Không | Không |
| `issuer` | String | Không | Không | Có thể |
| `accountName` | String | Không | Không | Có |
| `secretKey` | String | Không | Không | Credential tối quan trọng |
| `algorithm` | String | Không | SHA1 | Không |
| `digits` | int | Không | 6 | Không |
| `period` | int | Không | 30 | Không |

Model chưa có record version, timestamp, order, icon, counter hoặc tag.

### JSON contract

~~~json
{
  "id": "account-uuid",
  "issuer": "Example",
  "accountName": "user@example.invalid",
  "secretKey": "TEST_ONLY_REDACTED",
  "algorithm": "SHA1",
  "digits": 6,
  "period": 30
}
~~~

Key dùng camelCase. `fromJson` yêu cầu `id`, `issuer`, `accountName`, `secretKey`; record cũ thiếu algorithm/digits/period nhận default. Unit test xác minh cả round-trip đầy đủ và compatibility này.

### Bất biến

- `id` ổn định, duy nhất.
- `secretKey` là Base32 hợp lệ.
- `algorithm` thuộc SHA1/SHA256/SHA512.
- `digits` từ 6 đến 8; `period` dương.
- Mọi field round-trip không bị thay default âm thầm.
- Log/test output redact secret.

Local add hiện giữ nguyên algorithm/digits/period khi gán UUID.

## Local secure storage

### Format legacy v1

| Storage key | Giá trị |
|---|---|
| `authenticator_account_index` | JSON array account ID |
| Mỗi account ID | JSON `AuthenticatorAccount` |

Reader v2 chỉ dùng v1 để migration/rollback và không ghi mutation mới về format này.

### Format v2 đã triển khai

| Prefix | Vai trò |
|---|---|
| `ha:v2:record:` | Immutable account JSON, key gồm stable ID và transaction ID |
| `ha:v2:manifest:` | Generation cùng danh sách `id → recordKey` |
| `ha:v2:commit:` | Publication marker trỏ manifest đã verify |

Mutation được serialize trong data-source instance. Writer ghi/verify record và
manifest trước, commit marker sau cùng. Reader chọn committed generation mới nhất
hợp lệ và fallback generation trước nếu record/manifest mới hỏng.

Migration lần đầu:

1. Đọc legacy index và UUID-keyed record bằng `readAll`.
2. Bỏ dangling ID/record hỏng, recover orphan có UUID/payload hợp lệ.
3. Ghi và verify snapshot v2 rồi mới publish commit.
4. Giữ nguyên legacy key; chưa có compaction/secure-deletion claim.

Logout giữ nguyên namespace account. Local vault thuộc installation/profile local,
không thuộc Supabase user. Xem
[ADR-0002](adr/0002-versioned-local-vault-storage.md) và
[ADR-0003](adr/0003-offline-first-local-vault.md).

## UserEntity

| Field | Kiểu | Nullable | Nguồn |
|---|---|---:|---|
| `id` | String | Không | Supabase `User.id` |
| `email` | String | Có | Supabase `User.email` |
| `name` | String | Có | `name` trong user metadata |

Entity không chứa mật khẩu hoặc session token.

## SharedPreferences

| Key | Ý nghĩa | Nhạy cảm |
|---|---|---:|
| `biometric_enabled` | Yêu cầu local authentication | Không |
| `sync_enabled` | Cho phép sync thủ công | Không |
| `remembered_email` | Điền sẵn login email | Dữ liệu cá nhân |
| `remember_me_state` | Trạng thái checkbox | Không |
| Theme key của `ThemeProvider` | Theme đã chọn | Không |

Thay đổi key cần compatibility/migration cho bản cài hiện có.

## Supabase row contract đã triển khai

Migration `supabase/migrations/20260717163000_create_synced_accounts.sql` tạo
`public.synced_accounts`. Mapper tại data boundary chuyển model local camelCase
sang PostgreSQL snake_case:

| Local | Remote | Ghi chú |
|---|---|---|
| Session user | `user_id` | UUID owner, FK `auth.users` |
| `id` | `account_id` | UUID, cùng `user_id` tạo primary key |
| `issuer` | `issuer` | Text 1–255 |
| `accountName` | `account_name` | Text 1–512 |
| `secretKey` | `secret_key` | Plaintext credential 16–512 |
| `algorithm` | `algorithm` | SHA1/SHA256/SHA512 |
| `digits` | `digits` | 6–8 |
| `period` | `period` | 1–300 |
| — | `format_version` | Database default `1` |
| — | `updated_at` | Database default UTC khi insert |

Client download map đủ các field về entity. `hasRemoteData` select `account_id`;
last-upload query dùng `updated_at`. Unit test mapper và remote RLS contract test
xác minh round-trip algorithm/digits/period.

Build client cũ còn gửi `accountName`/`secretKey` không tương thích với schema
snake_case. Dữ liệu legacy không được import vào instance mới.

## Encrypted vault snapshot v2

**Đã triển khai trên self-hosted Supabase; client vẫn staged.** Table
`encrypted_vault_snapshots` giữ một snapshot hiện hành cho mỗi `user_id`:

| Field | Contract |
|---|---|
| `format_version` | Envelope version `1` |
| `revision` | Optimistic revision, bắt đầu từ 1 |
| `cipher` | `AES-256-GCM` |
| `nonce`, `ciphertext`, `auth_tag` | Snapshot encrypted/authenticated |
| `key_format_version` | Wrapped-DEK version `1` |
| `wrapped_key_*` | DEK wrap bằng recovery key do user giữ |
| `updated_at` | Server timestamp |

Plaintext trong cipher là JSON snapshot canonical gồm `format_version` và danh
sách `AuthenticatorAccount` sort theo stable ID. AAD bind purpose/version,
Supabase user ID và revision. RPC `publish_encrypted_vault_snapshot` chỉ commit
khi `expected_revision` khớp rồi tăng revision atomically. Conflict dùng SQLSTATE
`PT409`/HTTP 409; remote contract đã xác minh owner isolation và revision behavior.

Local DEK dùng secure-storage key `ha:e2ee:v1:dek:<supabase-user-id>` và không bị
xóa khi logout. Recovery code dạng `HA1-<base64url-256-bit>` không được lưu remote
plaintext. Migration v2 additive, không drop table plaintext.

## Remote identity và merge

- Owner: `user_id`.
- Record identity tại DB boundary: `account_id`.
- Compatibility merge identity hiện tại: stable `account_id`.

Remote record chưa có được persist với nguyên ID; label trùng nhưng ID khác được
giữ riêng. Khi cùng ID, local record tạm thắng. Protocol này vẫn chưa biểu diễn
revision conflict, deletion/tombstone hoặc concurrent device.

## Protocol thay đổi model

Persisted model change phải có:

1. Format/schema version.
2. Backward-compatible read.
3. Local/remote migration và recovery/rollback.
4. Round-trip test old-to-new và new-to-new.
5. Cross-client conflict behavior.
6. Cập nhật tài liệu này, `SUPABASE_INTEGRATION.md` và `SECURITY.md`.

Không dùng silent default để che record hỏng hoặc giá trị không hỗ trợ.
