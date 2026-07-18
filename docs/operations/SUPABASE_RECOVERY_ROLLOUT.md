# Rollout password recovery

Tài liệu này ghi lại rollout ngày **18 tháng 7 năm 2026**. Public URL, key, token,
email và user ID không được ghi vào repository.

## Kết quả

**Đã triển khai**:

- DNS trỏ recovery domain về host và Let’s Encrypt TLS hoạt động;
- Nginx Proxy Manager forward HTTPS tới recovery container qua
  `proxy-network`;
- container chạy non-root, read-only, `healthy`, chỉ publish loopback và tham gia
  `supabase_default` để Auth fetch template;
- canonical path `/reset-password/` trả trang cùng asset bằng absolute path;
- GoTrue allow-list exact recovery URL và fetch
  `GOTRUE_MAILER_TEMPLATES_RECOVERY` qua internal network;
- `.env` local bị Git ignore có `PASSWORD_RECOVERY_URL`, permission `0600`;
- source-controlled production overlays nằm ở
  `reset-password-web/compose.production.yml` và
  `supabase/docker-compose.recovery-web.yml`.

Theo contract đã chọn trong ADR-0004, email template đặt one-time `token_hash`
trong fragment. Fragment không đi qua reverse proxy; trang xóa URL material trước
khi gọi `verifyOtp` và không persist recovery session.

## Backup trước thay đổi

Backup pre-change nằm ngoài repository:

    /home/xuancanhit/backups/hyper-authenticator/pre-recovery-20260718T015223Z

Nó gồm Supabase `.env`, Supabase Compose, Nginx Proxy Manager Compose và full NPM
database dump. File đều có mode `0600`; checksum manifest đã verify pass. Artifact
có credential/config vận hành và không được tải lên Git hoặc CI.

## Bằng chứng xác minh

`reset-password-web/test.sh` pass static, JavaScript và hardened-container gate.
`reset-password-web/test-remote.sh` pass qua public HTTPS:

- canonical page và health endpoint;
- TLS, no-store, CSP, HSTS, referrer/frame/content-type header;
- public runtime config không chứa service-role/secret key;
- email template có `TokenHash` placeholder.

`scripts/supabase/test_remote_recovery_contract.sh` pass **8 kiểm tra** mà không
gửi email thật:

- tạo isolated user;
- generate recovery token hash với exact redirect;
- `verifyOtp` tạo recovery session;
- session cập nhật được mật khẩu;
- đăng nhập lại được bằng mật khẩu mới;
- token đã dùng và token malformed đều bị từ chối;
- isolated user được cleanup.

Sau test, `auth.users`, `auth.audit_log_entries`, `synced_accounts` và
`encrypted_vault_snapshots` đều 0 row. Audit log được dọn thủ công vì environment
này đang giữ zero-data baseline; không tự động xóa audit log production.

## Rollback

1. Dừng phát hành client có recovery URL mới.
2. Khôi phục Supabase `.env` và Compose từ backup, recreate riêng `auth`.
3. Xóa/disable recovery proxy host và certificate bằng Nginx Proxy Manager.
4. Stop recovery Compose project; không xóa backup trước khi rollback verify pass.
5. Xác minh Auth health và recovery behavior cũ trước khi mở lại traffic.

Không chỉ rollback template hoặc redirect riêng lẻ; ba phần client URL, allow-list
và template phải tương thích với nhau.

## Khoảng trống còn lại

- Chưa gửi/đọc email thật qua SMTP mailbox được kiểm soát; vì vậy delivery,
  anti-spam và body cuối cùng tại provider chưa được xác minh E2E.
- Chưa time-travel test token hết hạn trên remote instance.
- Cần alert certificate renewal, recovery availability và GoTrue mail failure.
- Nginx Proxy Manager image hiện do host quản lý; cần pin version/digest và có
  update rehearsal riêng.
