# Mô hình dữ liệu và storage contract

Tài liệu này mô tả shape đã triển khai trong source. Encrypted format được đề xuất nằm trong `E2EE_DESIGN.md`.

## AuthenticatorAccount

Source: `lib/features/authenticator/domain/entities/authenticator_account.dart`.

| Field | Kiểu Dart | Nullable | Default | Nhạy cảm |
|---|---|---:|---|---:|
| `id` | String | Không | Không có | Không |
| `issuer` | String | Không | Không có | Có thể |
| `accountName` | String | Không | Không có | Có |
| `secretKey` | String | Không | Không có | Credential tối quan trọng |
| `algorithm` | String | Không | SHA1 | Không |
| `digits` | int | Không | 6 | Không |
| `period` | int | Không | 30 | Không |

Model hiện tại không có `createdAt`, `updatedAt`, `orderIndex`, `iconPath`, `counter`, tag hoặc record version.

### JSON contract

Phương thức `toJson` hiện tại ghi:

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

Key dùng camelCase. `fromJson` bắt buộc `id`, `issuer`, `accountName`, `secretKey`; algorithm, digits và period bị thiếu sẽ nhận default.

### Bất biến bắt buộc

- `id` ổn định và duy nhất.
- `secretKey` là Base32 secret hợp lệ mà OTP library chấp nhận.
- `algorithm` là SHA1, SHA256 hoặc SHA512.
- `digits` nằm trong product contract được hỗ trợ; UI hiện validate từ 6 đến 8.
- `period` lớn hơn 0.
- Mọi field round-trip qua local và remote storage mà không âm thầm bị thay thế.
- Log và test report phải redact `secretKey`.

Implementation hiện tại vi phạm bất biến round-trip khi gán UUID mới. Xem `PROJECT_STATUS.md`.

## Bố cục local secure storage

Source: `lib/features/authenticator/data/datasources/authenticator_local_data_source.dart`.

| Storage key | Giá trị |
|---|---|
| `authenticator_account_index` | JSON array chứa account ID |
| Mỗi account ID | JSON của `AuthenticatorAccount` |

Create ghi record rồi cập nhật index. Delete xóa record rồi cập nhật index. Các thao tác nhiều bước này không transactional.

Cần định nghĩa recovery behavior khi:

- index có ID nhưng record bị thiếu;
- record tồn tại nhưng cập nhật index thất bại;
- JSON hỏng;
- ID trùng;
- đọc hoặc ghi secure storage thất bại.

## UserEntity

Source: `lib/features/auth/domain/entities/user_entity.dart`.

| Field | Kiểu Dart | Nullable | Nguồn |
|---|---|---:|---|
| `id` | String | Không | Supabase `User.id` |
| `email` | String | Có | Supabase `User.email` |
| `name` | String | Có | `name` trong Supabase `userMetadata` |

`UserEntity` không chứa mật khẩu hoặc session token.

## Key SharedPreferences

Dự án hiện dùng string constant ở nhiều feature thay vì một registry tập trung.

| Key | Ý nghĩa | Nhạy cảm |
|---|---|---:|
| `biometric_enabled` | Yêu cầu xác thực thiết bị qua OS | Không |
| `sync_enabled` | Hiển thị và cho phép sync thủ công | Không |
| `remembered_email` | Tiện ích cho form login | Dữ liệu cá nhân |
| `remember_me_state` | Trạng thái checkbox Remember Me | Không |
| `theme_mode` | Theme được chọn | Không |

Tên key theme chính xác phải được kiểm tra trong `ThemeProvider` trước migration. Thay đổi preference cần compatibility behavior cho bản cài hiện có.

## Contract row Supabase đã quan sát

Source: `lib/features/sync/data/datasources/supabase_sync_remote_data_source_impl.dart`.

Client hiện ghi map từ JSON `AuthenticatorAccount`, sau đó:

- đổi `id` thành `account_id`;
- thêm `user_id`;
- chèn `issuer`, `accountName`, `secretKey`, `algorithm`, `digits` và `period`.

Client cũng kỳ vọng:

- có `id` khi `hasRemoteData` thực hiện select;
- có `updated_at` khi đọc thời điểm upload gần nhất;
- `account_id` được map ngược thành entity `id` khi download.

Vì vậy contract quan sát được vừa có semantic `id` vừa có `account_id`, đồng thời field ứng dụng dùng camelCase. Tài liệu cũ từng mô tả field snake_case không khớp client.

Repository không track schema migration nên không thể tái lập chính xác production database.

## Định danh remote và merge

- Quyền sở hữu remote: `user_id`.
- Entity identity: `id` hoặc `account_id` tùy boundary.
- Merge identity hiện tại: issuer viết thường cộng `accountName` viết thường.

Merge identity này không phân biệt được secret rotation, label trùng hoặc hai account cùng nhãn. Nó cũng không biểu diễn deletion.

## Protocol thay đổi model

Mọi thay đổi model đã persist phải gồm:

1. Format hoặc schema version.
2. Read behavior tương thích ngược.
3. Local migration cùng rollback hoặc recovery strategy.
4. Remote migration nếu cloud data thay đổi.
5. Unit test cho round trip old-to-new và new-to-new.
6. Conflict behavior giữa các phiên bản client.
7. Cập nhật tài liệu này, `SUPABASE_INTEGRATION.md` và `SECURITY.md`.

Không dùng silent default để che giấu giá trị persist bị hỏng hoặc không được hỗ trợ.
