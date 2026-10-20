# ADR-0025: Google OAuth qua Supabase với PKCE

- Trạng thái: Chấp nhận theo yêu cầu triển khai Google sign-in của owner ngày 21-10-2026
- Ngày: 2026-10-21
- Owner: Project owner / Codex
- Thay thế: Bổ sung ADR-0022, không thay auth/password hoặc vault contract

## Bối cảnh

Owner yêu cầu đăng nhập/đăng ký bằng Google trên app đa nền tảng. Self-hosted
Supabase đã quản lý user identity và account sync; không tạo user database thứ hai.

## Quyết định

Một nút Tiếp tục với Google trên Login/Register, dùng Supabase OAuth PKCE.
Google chưa từng đăng nhập sẽ được Supabase tạo user sau khi provider xác minh;
verified-email identity linking theo chính sách Supabase, không tự merge user/vault.
Không xin Google Drive/contacts/offline access; chỉ openid/email/profile.

- Web redirect cùng origin về login; SDK xử lý code/session rồi router dùng
  allowlisted returnTo. Không nhận return URL tùy ý từ user.
- Android/iOS dùng external browser và app.hyperz.authenticator://auth/callback.
  App links và secure PKCE storage của SDK xử lý callback; tắt Flutter default
  deep linking để tránh GoRouter nhận raw callback làm route UI.
- Desktop dùng listener 127.0.0.1 ở port ngẫu nhiên, path 192-bit ngẫu nhiên,
  giới hạn thời gian, kiểm tra Host/method/path/code; đổi code trong app bằng PKCE.
- Extension dùng chrome.identity.launchWebAuthFlow, callback chromiumapp.org của
  extension ID cụ thể, thêm permission identity (không tabs/content_scripts).
  Bridge chỉ mở authorize endpoint Supabase production và callback đúng origin/path.

## Phương án đã cân nhắc

Native Google SDK yêu cầu thêm Android/iOS OAuth clients và dependency; browser
flow dùng một Web OAuth client cho Supabase callback và dùng được desktop.
Implicit tokens/hand-copy token bị loại: dùng one-time code + PKCE, không truyền
access/refresh token qua hosted relay hoặc extension messaging.

## Bảo mật và quyền riêng tư

Client secret chỉ ở private server environment; không trong Dart/asset/log/Git.
PKCE verifier giữ boundary secure native/extension đã có. Browser launch không
được emit authenticated; chỉ session/currentUser hợp lệ mới kích hoạt sync.
Callback/provider error không hiển thị raw trên UI. App lock và local ownership
giữ nguyên; logout giữ local mã. Custom scheme có risk interception, PKCE chống
redeem code bởi app không giữ verifier; cold/warm device acceptance vẫn cần test.

## Dữ liệu và compatibility

Không schema/vault migration. Provider enable và redirect allowlist additive;
không thay site/recovery URL cũ. Rollback UI/provider không xóa Google users,
identity hay TOTP; không downgrade vault writer v3.

## Xác minh và rollout

Unit/widget tests cho button/stream failure/race, callback validation và desktop
listener; JS bridge tests reject endpoints/callback lạ. Build Web/native/extension,
verify authorize redirect Google thật, user tự chọn/consent Google khi cần.
Server giữ private compose/env backup trước thay Auth service; recreate auth only,
không restart DB/Realtime. Google test/publishing audience quản lý tại Google Cloud.
