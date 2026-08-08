# Chính sách quyền riêng tư kỹ thuật

Tài liệu mô tả source hiện tại. Owner phải công bố URL, pháp nhân, contact và ngày
hiệu lực trước stable/store release.

## Dữ liệu local

- issuer, account label, TOTP secret, algorithm, digits, period;
- local-vault generation/commit metadata;
- secure cloud ownership/revision/fingerprint/tombstone metadata;
- theme, app-lock và session data do Supabase SDK quản lý.

Không đưa TOTP/auth credential vào analytics hoặc log.

## Dữ liệu Supabase

Khi đăng nhập, Supabase có thể xử lý:

- email/auth identity/session metadata;
- per-account UUID/revision/timestamp/tombstone;
- TOTP payload mã hóa trong Supabase Vault;
- payload plaintext tạm thời khi authenticated RPC decrypt cho đúng owner;
- network/server/audit log không được chứa payload.

Đây là server-managed encryption, không phải zero-knowledge E2EE. Backend/Vault
root-key holder nằm trong trust boundary.

## Import/export

Standard `otpauth` và Google migration QR chỉ tạo/đọc theo thao tác explicit.
Protected export yêu cầu OS auth và bị xóa khi timeout/background. QR/URI là
credential; người dùng phải kiểm soát camera, ảnh và thiết bị nhận.

## Xóa/logout

- Xóa local account commit ngay. Nếu account thuộc user đang đăng nhập, cloud
  tombstone được retry và thiết bị khác xóa ở lần sync sau.
- Logout dừng sync nhưng giữ local và cloud.
- Xóa Supabase user cascade xóa sync row; trigger dọn Vault secret live.
- App chưa có self-service delete-account UI.

## Third party

- Supabase: Auth, password recovery, Vault-backed account sync.
- GitHub Releases/Web hosting: phân phối artifact/site.
- Hệ điều hành: secure storage, local auth, camera/file API.

Không có advertising SDK/product analytics trong source hiện tại.

## Giới hạn

Secure storage, Vault, RLS/RPC, App Lock và Privacy Shield giảm rủi ro nhưng không
chống compromised backend/root key, OS/root/jailbreak, malicious extension,
screenshot hoặc administrator của thiết bị.

Nếu TOTP secret nghi lộ, phải rotate credential tại service phát hành TOTP.

## Retention

Live record tồn tại tới khi bị xóa/account bị xóa. Tombstone hiện giữ vô hạn để
chống stale resurrection; production policy phải định nghĩa retention trước khi
scale. Backup có retention/restore policy riêng và cần giữ Vault root key tương
ứng.

## Owner phải điền

- Pháp nhân/data controller, privacy URL và ngày hiệu lực.
- Support/security contact.
- Retention/deletion request process.
- Jurisdiction/subprocessor disclosure.
