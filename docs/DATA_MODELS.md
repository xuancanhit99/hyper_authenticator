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
DEK mới. Thiết bị chỉ giữ DEK cũ không thể decrypt current envelope; backup lịch
sử vẫn giữ envelope/key generation cũ.

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
