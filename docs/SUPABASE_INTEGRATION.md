# Tích hợp Supabase

Tài liệu này tách hành vi client quan sát được khỏi server control bắt buộc. Repository hiện không có Supabase migration có thể tái lập.

## Cấu hình client

Ứng dụng Flutter load:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

từ file `.env` ở root qua `flutter_dotenv`.

Quy tắc:

- Chỉ commit `.env.example` chứa placeholder.
- Không dùng `SUPABASE_SERVICE_ROLE_KEY` trong client application.
- Xem anon key là public client configuration, nhưng vẫn tránh trộn nhầm project test và production.
- Dùng Supabase project riêng cho development, test, staging và production.
- Ghi redirect URL và platform bundle ID theo từng environment.

`pubspec` hiện đóng gói `.env` như asset. Một ADR cấu hình trong tương lai phải quyết định giữ pattern này hay chuyển sang build-time configuration có thể tái lập.

## Thao tác authentication

Client đã triển khai:

- đăng ký bằng email, mật khẩu và name metadata tùy chọn;
- đăng nhập bằng email và mật khẩu;
- ánh xạ auth-state stream thành `UserEntity`;
- yêu cầu email khôi phục mật khẩu;
- cập nhật mật khẩu khi có recovery session đã xác thực;
- đăng xuất.

Hành vi sản phẩm hiện tại bắt buộc user đã xác thực để vào ứng dụng chính.

## Khôi phục mật khẩu

Mobile route `/update-password` đã có nhưng platform deep link và reset redirect chưa hoàn thiện.

Trang `reset-password-web` cũng xử lý Supabase `PASSWORD_RECOVERY` session. Trạng thái committed hiện chưa deploy được vì:

- `script.js` có URL và anon key để trống;
- Compose truyền build argument;
- Dockerfile không khai báo hoặc sử dụng argument tương ứng;
- khái niệm inject `env-config.js` ở runtime chưa được triển khai.

Cần chọn một recovery surface canonical, định nghĩa allowed redirect URL và bao phủ link hết hạn, đã dùng lại, malformed và cross-environment.

## Thao tác database hiện tại

Table constant: `synced_accounts`.

### Download

Client select mọi row có `user_id` bằng Supabase user ID hiện tại. Nếu có `account_id` mà không có `id`, client map `account_id` thành `id` trước khi gọi `AuthenticatorAccount.fromJson`.

### Upload

Client:

1. xóa mọi row có `user_id` khớp user hiện tại;
2. chuyển mỗi `AuthenticatorAccount` thành JSON;
3. đổi `id` thành `account_id`;
4. thêm `user_id`;
5. chèn toàn bộ danh sách.

### Trạng thái

- `hasRemoteData` select `id` và giới hạn một row.
- Thời điểm upload gần nhất select `updated_at` mới nhất.

Xem `DATA_MODELS.md` cho key mismatch quan sát được và `PROJECT_STATUS.md` cho rủi ro.

## Hành vi RLS bắt buộc

Phải bật RLS trên mọi table thuộc sở hữu user. Với `synced_accounts`, mỗi operation phải bắt buộc:

    auth.uid() = user_id

Policy cần có:

| Operation | `USING` | `WITH CHECK` |
|---|---|---|
| SELECT | `auth.uid() = user_id` | Không áp dụng |
| INSERT | Không áp dụng | `auth.uid() = user_id` |
| UPDATE | `auth.uid() = user_id` | `auth.uid() = user_id` |
| DELETE | `auth.uid() = user_id` | Không áp dụng |

Đây là requirement, không phải bằng chứng cấu hình đã deploy. Policy phải được track bằng migration và test trên môi trường Supabase local hoặc isolated.

## Negative test bắt buộc

- Anonymous client không thể đọc hoặc ghi row.
- User A không thể select row của User B.
- User A không thể insert row có `user_id` của User B.
- User A không thể đổi owner thành User B.
- User A không thể delete row của User B.
- Session hết hạn không thể sync.
- Distributed artifact không có service-role credential.

## Contract mục tiêu

Không ổn định hóa plaintext row contract hiện tại thành thiết kế dài hạn. Target contract nên có:

- record hoặc snapshot ID ổn định;
- quyền sở hữu `user_id`;
- `format_version`;
- authenticated payload đã encrypt;
- version hoặc concurrency metadata không nhạy cảm;
- `created_at` và `updated_at` được quản lý nhất quán;
- atomic snapshot publication hoặc optimistic concurrency theo record;
- migration state cho row plaintext cũ.

Schema chính xác cần ADR được chấp nhận và phải đồng bộ với `E2EE_DESIGN.md`.

## Checklist environment

Với mỗi environment, ghi bên ngoài repository secret:

- project reference và region;
- allowed redirect URL;
- email verification và recovery template;
- owner cấu hình SMTP;
- rate limit và abuse control;
- schema migration version;
- kết quả xác minh RLS;
- backup và restore policy;
- quyền truy cập và thời gian lưu log;
- owner key management và incident.

Không đặt project URL hoặc key thật trong tài liệu này.

## Failure behavior

Client phải phân biệt:

- chưa xác thực hoặc session hết hạn;
- bị từ chối authorization;
- validation failure;
- network unavailable;
- server conflict;
- schema không tương thích;
- upload một phần hoặc bị gián đoạn;
- encrypted payload version không được hỗ trợ.

Không biến merge một phần thành success và không retry thao tác phá hủy khi chưa có idempotency.
