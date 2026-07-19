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

`AuthenticatorAccount.toString()` luôn redact ID, issuer, account name và secret;
`AddAccountParams`/`UpdateAccountParams` cũng redact credential. Equality và
`toJson` vẫn giữ đủ field cho domain/persistence, vì vậy control log này không đổi
serialized shape hoặc round-trip contract.

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

### Windows storage layout

Application-support path canonical giữ metadata lịch sử:

    %APPDATA%\app.hyperz.authenticator\hyper_authenticator

Một số pre-release từng dùng sibling `Hyper Authenticator`. Trước DI, migrator chỉ
nhận `flutter_secure_storage.dat`, top-level `*.secure` và
`shared_preferences.json`; không theo symlink, không xóa nguồn và chỉ ghi marker
`.ha-storage-layout-v1-imported` sau atomic import thành công. Hai tập vault cùng
tồn tại nhưng khác tên file hoặc byte là conflict, không có merge tự động.

Windows plugin 3.1.2 của release `1.0.0+9` đã dùng DPAPI map
`flutter_secure_storage.dat` làm primary; MethodChannel `*.secure` là backward
compatibility cho phiên bản cũ hơn. Sau khi physical layout đã canonical, current
plugin đọc cả hai dạng và local datasource publish logical account sang COW v2.
Các field `algorithm`, `digits`, `period` phải round-trip; source ở sibling không
bị app layout migrator xóa.

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

Xoay recovery key không đổi schema/key format và không đổi DEK. Client tạo KEK
mới, re-wrap DEK, re-encrypt snapshot bằng nonce mới và atomic publish revision
kế tiếp. Vì table chỉ giữ current snapshot, wrapped key mới thay wrapped key cũ;
backup lịch sử vẫn có thể chứa wrapped key cũ.

Xoay vault key cũng không đổi schema/key format nhưng sinh DEK và recovery key
mới. Current snapshot được re-encrypt bằng DEK mới; ciphertext và wrapped DEK mới
được publish trong cùng RPC/revision. Sau verify, secure storage thay DEK cũ bằng
DEK mới. Thiết bị active chỉ giữ DEK generation cũ sẽ đọc exact HPKE wrap của
installation/current session, verify membership proof, decrypt current envelope
rồi mới persist DEK generation mới. Thiết bị bị exclude, mất private key hoặc có
wrap/proof sai vẫn phải dùng recovery key; backup lịch sử giữ generation cũ.

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

Authorization không thêm column vào encrypted table. JWT phải có `session_id` do
Supabase Auth cấp; helper `private.is_current_auth_session_active()` chỉ trả true
khi `auth.sessions.id`, `auth.sessions.user_id` và optional `not_after` còn hợp lệ
cho `auth.uid()`. Session ID/token không được persist trong snapshot hoặc
SharedPreferences của feature sync.

## Metadata thiết bị

SharedPreferences giữ theo Supabase user ID:

- sync enabled/disabled;
- last-seen remote revision.

SharedPreferences còn giữ một installation UUID v4 không phải credential, dùng
làm display metadata ổn định cho device registry. UUID này không xác thực request,
không quyết định current session và có thể được tạo lại khi local preference hỏng.

Table `public.authenticator_device_sessions` là metadata server-side:

| Column | Contract |
|---|---|
| `registration_id uuid` | Opaque public identifier để targeted revoke |
| `user_id uuid` | Owner lấy từ `auth.uid()` |
| `session_id uuid` | Bind server-side từ JWT; không trả về client |
| `installation_id uuid` | Pseudonymous display metadata do client cung cấp |
| `display_name`, `platform` | Nhãn tối đa 80 ký tự và platform allowlist |
| `registered_at`, `last_seen_at` | Registry timestamps |
| `revoked_at` | Soft marker trước khi xóa target `auth.sessions` row |

Table bật + force RLS và không grant direct client access. List RPC chỉ trả
`registration_id`, display/platform/timestamp và server-derived `is_current`; nó
không trả session ID, IP hoặc user agent. Record inactive quá 30 ngày được prune
khi một active session đăng ký.

Không lưu TOTP secret, DEK, recovery key hoặc auth token trong SharedPreferences
hay device registry.

## Device-specific wrapped DEK — **Đã triển khai server và client**

ADR-0012 đã được duyệt. Migration production thêm `key_generation` monotonic,
`device_wrap_version`, device public-key table và đúng một current-generation HPKE
wrap cho mỗi device key active. Client model/repository/coordinator đã được inject;
Linux isolated runtime đã pass. GitHub Preview hiện tại vẫn là binary cũ.

~~~json
{
  "format_version": 1,
  "key_generation": 2,
  "kem": "DHKEM-X25519-HKDF-SHA256",
  "kdf": "HKDF-SHA256",
  "aead": "AES-256-GCM",
  "encapsulated_key": "canonical padded base64url của 32 byte",
  "ciphertext": "canonical padded base64url của 32 byte",
  "auth_tag": "canonical padded base64url của 16 byte"
}
~~~

- Device private key và random binding secret 256-bit nằm trong platform secure
  storage theo user + installation; không vào SharedPreferences hoặc server response.
- HPKE `info`/AAD bind user, installation, opaque device-key ID, generation và
  recipient public key bằng encoding field có unsigned 32-bit length-prefix;
  không dùng chuỗi delimiter có thể collision.
- Parser fail closed với suite/version lạ, field oversized, base64url
  non-canonical hoặc decoded length sai trước khi gọi AEAD.
- Membership proof theo device dùng HMAC-SHA256 với key HKDF domain-separated từ
  current DEK; client có DEK phải verify trước confirm và trước khi include device
  trong generation mới. Một vault membership verifier riêng cũng dẫn xuất từ DEK,
  bind user + generation và chỉ lưu trong bảng `private` không cấp client access;
  RPC so khớp verifier để session không biết DEK không thể self-enroll bằng proof giả.
- Binding secret chỉ dùng resume server record qua TLS; migration chỉ lưu SHA-256
  của random secret 256-bit, không trả hash/raw secret qua RPC. Nó không wrap DEK
  và không thay membership proof.
- Device state đi `pending → wrapped → active`; chỉ target session được confirm
  sau local unwrap. Rotation tăng generation đúng một, thay exact wrap set trong
  cùng transaction và chuyển device bị loại sang `revoked` đồng thời xóa auth session.
- Nếu secure storage mất device private key nhưng người dùng còn HA1, client dẫn
  xuất đúng vault verifier để thay key trên cùng installation; server revoke key/
  session cũ trước khi bind key mới. Verifier sai không được thay key.
- `device_wrap_version=1` chặn legacy publish RPC; v2 normal publish bind exact
  generation và active device binding để client cũ không làm lệch DEK/wrap set.
- Recovery-key wrapped DEK v1 tiếp tục là break-glass path.

## Compatibility plaintext

`synced_accounts` dùng snake_case và từng chứa `secret_key` plaintext. Runtime DI
không đăng ký datasource/repository/use case cũ; release guard vẫn chặn. Table chỉ
được giữ cho migration/rollback có kiểm soát và phải backup trước khi drop.

## Versioning và migration

- Unknown future encrypted format bị từ chối trước decrypt.
- Không downgrade hoặc silently default field đã persist.
- Schema E2EE là additive; plaintext table chưa bị drop trong rollout này.
- Migration phá hủy table cũ cần backup, compatibility audit và rollback riêng.
