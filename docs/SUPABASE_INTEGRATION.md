# Tích hợp Supabase

Tài liệu này tách client behavior đã triển khai khỏi server control bắt buộc. Repository hiện chưa có Supabase migration có thể tái lập.

## Cấu hình client

`AppConfig` đọc compile-time environment:

- `SUPABASE_URL`;
- `SUPABASE_PUBLISHABLE_KEY`;
- `SUPABASE_ANON_KEY` chỉ là fallback tương thích cấu hình cũ.

Development:

    cp .env.example .env
    flutter run --dart-define-from-file=.env

`.env` bị Git ignore và không được khai báo trong Flutter assets. Analyze/test/build không cần configuration; runtime bootstrap cần URL và publishable key hợp lệ.

Quy tắc:

- Chỉ commit `.env.example` có placeholder.
- Không dùng service-role key trong Flutter, static web hoặc CI client build.
- Publishable/anon key là public client configuration, không phải authorization boundary.
- Tách project development, test, staging và production.
- Ghi allowed redirect URL và application identifier theo environment.

## Authentication

Client đã có đăng ký email/password cùng name metadata, đăng nhập, auth-state stream, gửi recovery email, cập nhật mật khẩu và đăng xuất. Router hiện bắt buộc user đã xác thực để dùng ứng dụng chính.

Logout không xóa TOTP local. Quyền sở hữu local data giữa nhiều Supabase user vẫn cần product decision rõ ràng.

## Khôi phục mật khẩu

Mobile route `/update-password` có sẵn nhưng universal/custom link chưa hoàn thiện. `reset-password-web` cũng lắng nghe `PASSWORD_RECOVERY`, nhưng chưa deploy-ready vì JavaScript config trống và Docker build argument chưa được inject.

Cần chọn recovery surface canonical, whitelist redirect URL và test link thành công, hết hạn, reuse, malformed cùng cross-environment.

## Contract database đã quan sát

Table: `synced_accounts`.

### Download

Client select mọi row có `user_id` bằng user hiện tại. `account_id` được map về entity key `id` trước `AuthenticatorAccount.fromJson`.

### Upload

1. Xóa mọi row có `user_id` của user hiện tại.
2. Chuyển mỗi account thành JSON.
3. Đổi `id` thành `account_id` và thêm `user_id`.
4. Chèn toàn bộ danh sách.

### Truy vấn trạng thái

- `hasRemoteData` select `account_id` và limit một row.
- Last-upload time lấy `updated_at` mới nhất.

Contract field application hiện dùng camelCase. Không có migration nên không thể chứng minh schema production khớp contract này.

## RLS bắt buộc

RLS phải bật cho mọi table user-owned. Với `synced_accounts`:

    auth.uid() = user_id

| Operation | `USING` | `WITH CHECK` |
|---|---|---|
| SELECT | `auth.uid() = user_id` | — |
| INSERT | — | `auth.uid() = user_id` |
| UPDATE | `auth.uid() = user_id` | `auth.uid() = user_id` |
| DELETE | `auth.uid() = user_id` | — |

Đây là requirement, không phải bằng chứng policy đã deploy. Schema/policy cần migration version control và test Supabase local hoặc isolated.

Negative test bắt buộc:

- anonymous không đọc/ghi row;
- User A không select/update/delete row User B;
- User A không insert hoặc đổi owner sang User B;
- session hết hạn không sync;
- distributed artifact không có service-role credential.

## Contract mục tiêu

Không ổn định hóa plaintext row hiện tại thành thiết kế dài hạn. Target cần:

- stable record/snapshot ID và `user_id`;
- `format_version`;
- authenticated encrypted payload;
- revision/concurrency metadata không nhạy cảm;
- atomic snapshot publication hoặc optimistic concurrency;
- migration rõ cho row plaintext cũ.

Schema chính xác cần ADR và phải đồng bộ `E2EE_DESIGN.md`.

## Failure behavior

Client phải phân biệt unauthenticated, authorization denied, validation, network, conflict, schema mismatch, interrupted upload và unsupported encrypted format. Merge một phần không được emit success; destructive retry phải có idempotency trước.

## Checklist environment

Quản lý ngoài repository secret:

- project reference/region và owner;
- allowed redirect URL;
- email verification/recovery template;
- SMTP, rate-limit và abuse control;
- migration version và RLS test result;
- backup/restore, log retention và incident owner.
