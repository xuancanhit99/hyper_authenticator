# Mô hình dữ liệu

Không đặt secret thật trong ví dụ, fixture hoặc log. Chuỗi minh họa bên dưới chỉ
mô tả shape.

## `AuthenticatorAccount`

~~~json
{
  "id": "uuid-stable",
  "issuer": "Service",
  "accountName": "user@example.invalid",
  "secretKey": "TEST_ONLY_BASE32_PLACEHOLDER",
  "algorithm": "SHA256",
  "digits": 8,
  "period": 45
}
~~~

| Field | Contract |
|---|---|
| `id` | UUID stable qua add/update/restore/sync |
| `issuer` | Không rỗng |
| `accountName` | Không rỗng |
| `secretKey` | Base32 đã normalize; credential |
| `algorithm` | `SHA1`, `SHA256` hoặc `SHA512` |
| `digits` | 6–8 |
| `period` | Số nguyên dương |

Logo không phải persisted field. UI sinh avatar từ `issuer` nên việc loại icon
asset không cần migration data.

## Local vault v2

Secure storage chứa immutable generation:

- record account theo generation + stable ID;
- manifest có version, generation ID và danh sách ID;
- commit marker trỏ generation active;
- legacy keys được giữ trong giai đoạn compatibility.

Mutation ghi generation mới rồi mới đổi commit marker. Reader validate manifest,
record và model; nếu active generation lỗi thì thử rollback generation. Compaction
giữ hai generation hợp lệ gần nhất, không xóa active/rollback trước khi generation
mới được verify.

## Encrypted plaintext snapshot trước khi mã hóa

Payload canonical là object versioned chứa danh sách account sort theo stable ID.
Nó chỉ tồn tại trong memory trước/ sau AES-GCM và không được gửi tới backend.

~~~json
{
  "formatVersion": 1,
  "accounts": [
    {
      "id": "uuid-stable",
      "issuer": "Service",
      "accountName": "user@example.invalid",
      "secretKey": "TEST_ONLY_BASE32_PLACEHOLDER",
      "algorithm": "SHA256",
      "digits": 8,
      "period": 45
    }
  ]
}
~~~

## Encrypted envelope v1

~~~json
{
  "formatVersion": 1,
  "revision": 3,
  "cipher": "AES-256-GCM",
  "nonce": "base64url",
  "ciphertext": "base64url",
  "authTag": "base64url"
}
~~~

Associated authenticated data bind purpose string, format version, Supabase user
ID và revision. Thay user/revision/envelope field làm authentication thất bại.

## Wrapped DEK v1

~~~json
{
  "keyFormatVersion": 1,
  "wrappedKeyNonce": "base64url",
  "wrappedKeyCiphertext": "base64url",
  "wrappedKeyAuthTag": "base64url"
}
~~~

Recovery key 256-bit có prefix/version `HA1-`; backend chỉ giữ wrapped DEK. DEK
plaintext được giữ theo Supabase user ID trong platform secure storage.

## PostgreSQL encrypted contract

Table `public.encrypted_vault_snapshots`:

| Column | Ý nghĩa |
|---|---|
| `user_id uuid` | PK/FK tới `auth.users`; tenant owner |
| `format_version smallint` | Envelope format, hiện bằng 1 |
| `revision bigint` | Monotonic revision > 0 |
| `cipher text` | Hiện chỉ `AES-256-GCM` |
| `nonce`, `ciphertext`, `auth_tag` | Encrypted snapshot |
| `key_format_version` | Wrapped key format, hiện bằng 1 |
| `wrapped_key_*` | DEK được wrap bằng recovery key |
| `updated_at timestamptz` | Server timestamp |

`publish_encrypted_vault_snapshot` nhận expected revision và toàn bộ encrypted
field. Nó insert revision 1 khi expected=0 hoặc update revision+1 khi current
revision khớp; ngược lại trả `PT409`.

## Metadata thiết bị

SharedPreferences giữ theo Supabase user ID:

- sync enabled/disabled;
- last-seen remote revision.

Không lưu TOTP secret, DEK hoặc recovery key trong SharedPreferences.

## Compatibility plaintext

`synced_accounts` dùng snake_case và từng chứa `secret_key` plaintext. Runtime DI
không đăng ký datasource/repository/use case cũ; release guard vẫn chặn. Table chỉ
được giữ cho migration/rollback có kiểm soát và phải backup trước khi drop.

## Versioning và migration

- Unknown future encrypted format bị từ chối trước decrypt.
- Không downgrade hoặc silently default field đã persist.
- Schema E2EE là additive; plaintext table chưa bị drop trong rollout này.
- Migration phá hủy table cũ cần backup, compatibility audit và rollback riêng.
