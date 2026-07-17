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

| Storage key | Giá trị |
|---|---|
| `authenticator_account_index` | JSON array account ID |
| Mỗi account ID | JSON `AuthenticatorAccount` |

Create ghi record rồi cập nhật index; delete xóa record rồi cập nhật index. Hai bước không transactional. Cần recovery cho index trỏ record thiếu, orphan record, JSON hỏng, ID trùng và storage failure.

Logout giữ nguyên namespace account. Storage ownership khi nhiều Supabase user đăng nhập cùng thiết bị chưa được quy định.

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

## Supabase row contract đã quan sát

Client upload JSON account rồi:

- đổi `id` thành `account_id`;
- thêm `user_id`;
- giữ `issuer`, `accountName`, `secretKey`, `algorithm`, `digits`, `period`.

Client download map `account_id` về `id`. `hasRemoteData` select `account_id`; last-upload query dùng `updated_at`. Repository chưa có schema migration nên không thể tái lập chính xác database production.

## Remote identity và merge

- Owner: `user_id`.
- Record identity tại DB boundary: `account_id`.
- Merge identity hiện tại: issuer viết thường + accountName viết thường.

Identity merge không biểu diễn secret rotation, label trùng, deletion hoặc conflict hai thiết bị.

## Protocol thay đổi model

Persisted model change phải có:

1. Format/schema version.
2. Backward-compatible read.
3. Local/remote migration và recovery/rollback.
4. Round-trip test old-to-new và new-to-new.
5. Cross-client conflict behavior.
6. Cập nhật tài liệu này, `SUPABASE_INTEGRATION.md` và `SECURITY.md`.

Không dùng silent default để che record hỏng hoặc giá trị không hỗ trợ.
