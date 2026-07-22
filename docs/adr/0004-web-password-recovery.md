# ADR-0004: Web là password-recovery surface canonical

- Trạng thái: Chấp nhận
- Ngày: 2026-07-18
- Owner: canhvx
- Thay thế: P-005
- Bị thay thế bởi:

## Bối cảnh

Flutter dùng PKCE và code verifier nằm ở client đã yêu cầu recovery. Một browser
khác không thể exchange code đó. Dự án cần một flow nhất quán cho mọi platform.

## Quyết định

`reset-password-web` là surface canonical. Flutter gửi recovery request với public
HTTPS URL đã cấu hình. Template self-hosted tạo fragment
`#token_hash={{ .TokenHash }}&type=recovery`; Web gọi `verifyOtp`, cập nhật password,
xóa URL material và sign out local session. Mobile `/update-password` chỉ được giữ
tạm thời cho compatibility, không phải đường production.

## Phương án đã cân nhắc

### Deep link riêng cho từng platform

Giữ PKCE end-to-end nhưng tăng đáng kể entitlement, association file, installer và
test matrix. Có thể bổ sung sau, không là canonical flow hiện tại.

### Implicit access/refresh token trong fragment

Hoạt động client-side nhưng mang session material dài hơn trong browser. Chỉ giữ
compatibility, template mới phải dùng one-time token hash.

## Hệ quả

- Một URL/template và test matrix chung cho sáu platform.
- Recovery hosting, SMTP, redirect allow-list và availability trở thành release gate.
- Password recovery không khôi phục E2EE recovery key.

## Bảo mật và quyền riêng tư

Fragment không đi tới reverse proxy. Web không persist session, không log raw error,
dùng no-store/CSP/HSTS và chỉ nhận publishable key. Email prefetch vẫn phải test;
nếu provider consume link, chuyển sang OTP-entry flow trong ADR mới.

## Dữ liệu và compatibility

Không đổi auth user data. Template và `PASSWORD_RECOVERY_URL` phải rollout cùng
nhau; rollback về template cũ chỉ được phép khi client flow tương ứng còn test.

## Xác minh

JavaScript harness, container hardening test và E2E isolated email test cho success,
expired, malformed, reuse và cross-environment.

## Rollout

1. Deploy Web HTTPS.
2. Allow-list URL chính xác.
3. Serve template từ URL mà Auth container truy cập được.
4. Cấu hình `GOTRUE_MAILER_TEMPLATES_RECOVERY` và smoke test trước production.

## Cập nhật triển khai — 22-07-2026

Recovery Web, redirect/template và remote token contract 8/8 đã deploy; SMTP
mailbox delivery và expired-link E2E được owner hoãn riêng cho GitHub Preview,
với cảnh báo công khai. Chúng vẫn là gate bắt buộc trước khi quảng bá email
delivery hoặc phát hành stable/store. Câu “release gate” và bước smoke production
phía trên là quyết định mục tiêu ban đầu, không phải bằng chứng mailbox hiện đã pass.
