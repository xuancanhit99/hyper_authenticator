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

## Standard otpauth URI — transient

Mỗi standard Key URI Format payload mô tả đúng một TOTP account. Parser chỉ nhận
scheme/type TOTP canonical, một label path và các query field `secret`, `issuer`,
`algorithm`, `digits`, `period`; mỗi security-relevant field xuất hiện tối đa một
lần. Unknown query field không được persist. Import URI tối đa 16 KiB.

Label encode `issuer:accountName`; query `issuer` là nguồn canonical khi có mặt để
issuer hoặc account name chứa dấu hai chấm vẫn round-trip. Secret được normalize
Base32 và bỏ padding khi export. Algorithm được normalize về
SHA1/SHA256/SHA512; digits 6–8 và period nguyên dương giữ nguyên, không tự thay
default.

Import payload chỉ tồn tại trong scanner/parser memory. Preview chỉ nhận
`ParsedTotpAccount`, không render secret; confirm dùng cùng atomic
append/exact-dedupe contract với Google migration import. Account mới nhận UUID;
exact duplicate giữ account hiện có.

Exporter validate toàn bộ selection trước khi trả list, giới hạn 100 account và
1.800 ký tự mỗi URI. `TotpUriExportPart` chứa URI, index và total nhưng
`toString()` luôn redact URI. Mỗi part tương ứng một QR và chỉ tồn tại trong
protected page state sau fresh OS auth, tối đa 60 giây; không serialize vào vault,
BLoC, route, clipboard, file hoặc Supabase.

## Google Authenticator migration payload — transient

`otpauth-migration://offline?data=...` là Base64 của protobuf schema được tái
dựng, không phải persisted format hoặc API Google được công bố. Import nhận
version 1 và wire shape version 2 đã quan sát từ Google Authenticator 7.2:

- `MigrationPayload`: repeated OTP parameters, version, batch size/index/id;
- OTP parameters chung: secret bytes, name, issuer, algorithm, digits, type và
  counter;
- version 2 có thêm một opaque identifier ở field 8. Parser chỉ kiểm tra
  bounded/non-empty rồi bỏ field này, không persist hoặc dùng làm identity.

Parser chỉ nhận TOTP, SHA1/SHA256/SHA512 và 6/8 digits. Secret bytes được chuyển
sang Base32; period là 30 giây vì payload không có period. Prefix
`issuer:account` trong name được normalize; issuer thực sự trống dùng nhãn hiển
thị `Không xác định` và được user nhìn thấy trong preview.

Payload và batch collector chỉ tồn tại trong memory. Sau preview/confirm, account
được validate lại, nhận UUID mới và append vào local vault bằng một COW commit.
Exact duplicate dùng issuer, account name, secret không padding, algorithm,
digits và period canonical để bỏ qua. Summary chỉ chứa `importedCount` và
`duplicateCount`, không mang account hoặc secret.

Encoder export vẫn phát version 1 với field mapping chung, positive random
`int32` batch ID và giữ thứ tự account; Google Authenticator 7.2 trên Android AVD
đã nhận format này. Mỗi đợt tối đa 100 account/100 part; từng URI giới hạn 1.800
ký tự, text 2 KiB và secret decoded 1 KiB. TOTP period khác 30 giây hoặc digits
khác 6/8 bị từ chối vì schema Google không round-trip được semantics đó.
`GoogleAuthenticatorMigrationExportPart.toString()` redact URI.

Export part chỉ tồn tại trong state nội bộ của page sau fresh OS auth, tối đa 60
giây; không serialize vào vault, BLoC, route extra, clipboard, file hoặc Supabase.

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

## Portable encrypted backup file v1

File `.hyauth` là canonical compact JSON, tối đa 8 MiB:

~~~json
{
  "format": "hyper-authenticator-encrypted-backup",
  "format_version": 1,
  "kdf": {
    "name": "argon2id",
    "version": 19,
    "memory_kib": 19456,
    "iterations": 2,
    "parallelism": 1,
    "salt": "base64url-no-padding"
  },
  "cipher": {
    "name": "aes-256-gcm",
    "nonce": "base64url-no-padding",
    "ciphertext": "base64url-no-padding",
    "auth_tag": "base64url-no-padding"
  }
}
~~~

Salt dài 16 byte, nonce 12 byte, auth tag 16 byte và Argon2id output 32 byte.
Decoder chỉ nhận Argon2 v19, memory 19–64 MiB, iteration 2–5, parallelism 1–4 và
`memory_kib >= 8 * parallelism` trước khi chạy KDF. Encoder v1 hiện dùng
19 MiB/2/1. AAD canonical bind purpose, format/name/version, toàn bộ KDF
metadata/salt, cipher name và nonce.

Plaintext v1 chỉ tồn tại trong memory sau AEAD authentication:

~~~json
{
  "payload_format_version": 1,
  "created_at": "2026-07-27T10:30:00.000Z",
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

Payload giữ đúng local order và stable ID, tối đa 10.000 account. Decoder yêu cầu
exact key set/type, unique ID, issuer/account name canonical, Base32 normalized,
algorithm SHA1/SHA256/SHA512, digits 6–8, period 1–86.400 giây cùng field-size
bound. Restore là full replacement; không sinh UUID mới, merge hoặc dedupe.

`EncryptedBackupRestorePreview` chỉ mang `createdAt`, count và issuer/account
name/algorithm/digits/period; decrypted `AuthenticatorAccount` nằm trong private
BLoC memory. Event password và snapshot/selection/preview đều redact
`toString()`.

Format này độc lập với cloud envelope bên dưới. Nó không chứa Supabase user,
revision, DEK/wrapped key hoặc recovery key và không được upload tự động.

## Cloud encrypted plaintext snapshot trước khi mã hóa

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

## Cloud encrypted envelope v1

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
DEK mới. Trước khi tạo next-generation wrap, generic client verify
current-generation wrap + membership proof của mọi active device bằng DEK hiện
tại; entry thiếu, stale hoặc giả làm preparation fail trước publish. Tất cả active
device đã verify đều nhận wrap mới vì UI hiện chưa hỗ trợ per-device exclusion.
Thiết bị chỉ giữ DEK generation cũ sẽ đọc exact HPKE wrap của installation/current
session, verify proof, decrypt current envelope rồi mới persist DEK mới. Thiết bị
không có wrap do một explicit backend exclusion, mất private key hoặc có wrap/proof
sai phải dùng recovery key; backup lịch sử vẫn giữ generation cũ.

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
field. Terminal protocol contract chỉ cho legacy RPC insert revision 1 khi
`expected_revision=0`; request update qua RPC này bị từ chối với
`device_key_protocol_required`. Mọi update tiếp theo dùng
`publish_encrypted_vault_snapshot_v2`: hàm khóa exact user/revision/generation row
bằng `FOR UPDATE`, yêu cầu `device_wrap_version=1` và active current-device binding,
rồi mới tăng revision. Version stale trả `PT409`; protocol `0` bị từ chối trước
mutation.

Authorization không thêm column vào encrypted table. JWT phải có `session_id` do
Supabase Auth cấp; helper `private.is_current_auth_session_active()` chỉ trả true
khi `auth.sessions.id`, `auth.sessions.user_id` và optional `not_after` còn hợp lệ
cho `auth.uid()`. Session ID/token không được persist trong snapshot hoặc
SharedPreferences của feature sync.

## Metadata thiết bị

SharedPreferences giữ theo Supabase user ID:

- backup cloud E2EE enabled/disabled;
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
Linux isolated runtime và Android/iOS two-session runtime đã pass. GitHub Preview
`v1.1.0-preview.3` chứa surviving-device auto-unwrap fix.

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
  current DEK; client có DEK phải verify trước confirm. Khi rotate, client verify
  wrap + proof của **toàn bộ** active set ở current generation trước khi tạo bất kỳ
  wrap mới nào, nên một entry giả/stale làm operation fail closed thay vì nhận DEK
  mới. Một vault membership verifier riêng cũng dẫn xuất từ DEK, bind user +
  generation và chỉ lưu trong bảng `private` không cấp client access; RPC so khớp
  verifier để session không biết DEK không thể self-enroll bằng proof giả.
- Binding secret chỉ dùng resume server record qua TLS; migration chỉ lưu SHA-256
  của random secret 256-bit, không trả hash/raw secret qua RPC. Nó không wrap DEK
  và không thay membership proof.
- Device state đi `pending → wrapped → active`; chỉ target session được confirm
  sau local unwrap. Rotation tăng generation đúng một và backend thay exact wrap
  set trong cùng transaction; ID nằm trong explicit exclusion được chuyển sang
  `revoked` đồng thời xóa auth session. Generic client hiện truyền exclusion rỗng,
  nên khả năng backend này chưa phải cryptographic revoke cho người dùng.
- Nếu secure storage mất device private key nhưng người dùng còn HA1, client dẫn
  xuất đúng vault verifier để thay key trên cùng installation; server revoke key/
  session cũ trước khi bind key mới. Verifier sai không được thay key.
- Legacy publish RPC chỉ tạo revision 1. Mọi update dùng v2, khóa exact snapshot row
  rồi yêu cầu `device_wrap_version=1`, exact generation và active device binding;
  protocol `0`/client cũ không thể update hoặc race với protocol confirmation.
- Recovery-key wrapped DEK v1 tiếp tục là break-glass path.

## Đường sync plaintext đã được loại bỏ

`public.synced_accounts` từng chứa `secret_key` plaintext. Datasource, mapper,
repository và use case của path này đã bị xóa khỏi client. Compile define
`ALLOW_INSECURE_PLAINTEXT_SYNC` chỉ còn là poison sentinel; mọi build từ chối
`true`.

Migration loại bỏ cuối cùng lấy `ACCESS EXCLUSIVE` lock trước khi đếm row trong
transaction. Bảng không tồn tại thì migration idempotent; bảng rỗng được drop
ngay trong nhánh đã lock, không `CASCADE`; còn bất kỳ row nào thì toàn bộ
transaction abort với `plaintext_legacy_rows_present`, giữ nguyên table/data để
operator backup và migrate thủ công. Restore backup cũ phải chạy lại zero-row
preflight và migration trước khi nhận traffic.

## Versioning và migration

- Unknown future encrypted format bị từ chối trước decrypt.
- Không downgrade hoặc silently default field đã persist.
- Device-wrap schema giữ additive history; hardening cuối cùng chỉ cắt quyền update
  protocol `0` sau revision đầu tiên.
- Plaintext retirement là destructive và fail closed khi còn row. Production
  apply ngày 22-07-2026 đã pass fresh full backup, checksum/off-host copy,
  zero-row evidence và restore rehearsal; future restore/instance phải lặp lại
  các gate này. Rollback dùng backup tương thích, không bật lại plaintext client path.
