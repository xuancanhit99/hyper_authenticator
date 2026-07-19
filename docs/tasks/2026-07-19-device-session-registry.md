# Task: Registry và thu hồi riêng từng phiên thiết bị

- Trạng thái: Đang xác minh CI
- Bắt đầu: 2026-07-19
- Owner: Codex
- Issue hoặc ADR liên quan: ADR-0011

## Mục tiêu

Người dùng đã đăng nhập có thể xem các phiên Hyper Authenticator đã tự đăng ký và
đăng xuất riêng một phiên từ thiết bị hiện tại. Access JWT của phiên bị thu hồi
phải mất quyền đọc/ghi encrypted vault ngay, không ảnh hưởng local vault hoặc phiên
hiện tại.

## Ngoài phạm vi

- Không coi registry ID là authenticator hoặc permanent device ban.
- Không triển khai device-specific DEK wrap, trusted-device transfer hoặc Web E2EE.
- Không liệt kê session cũ chưa từng chạy client có registry; bulk revoke vẫn là
  fallback cho các phiên đó.

## Acceptance criteria

- [x] Client không gửi `user_id` hoặc `session_id`; backend lấy cả hai từ JWT.
- [x] Direct table access bị chặn; RPC chỉ trả record của current user/session active.
- [x] Current session không tự thu hồi qua device RPC.
- [x] Thu hồi riêng một record xóa đúng `auth.sessions` row và chặn RLS/RPC ngay.
- [x] Cross-tenant registry ID không thể list hoặc revoke.
- [x] UI phân biệt thiết bị hiện tại, chống double submit và mô tả rõ re-login.
- [x] Migration additive, rollback không đụng encrypted snapshot hoặc local vault.

## Bằng chứng hiện tại

- Source path: `supabase/migrations/20260718230000_enforce_active_vault_sessions.sql`
- Cách tái hiện: Settings hiện chỉ có `SignOutScope.others`, không list/revoke riêng.
- Test hiện có: encrypted migration/remote contract chứng minh bulk revoke chặn
  access JWT cũ.
- Giả định: `supabase_admin` production có SELECT/DELETE trên `auth.sessions`; probe
  read-only ngày 2026-07-19 xác nhận cả hai privilege.

## Đánh giá rủi ro

- Lộ credential: registry ID và installation ID là pseudonymous metadata, không
  phải token; RPC không trả `session_id`, IP hoặc user agent.
- Mất dữ liệu local: không xóa local vault, DEK hoặc preference sync.
- Mất dữ liệu cloud: không sửa encrypted snapshot; chỉ thu hồi auth session sau
  xác nhận rõ.
- Migration: additive table + RPC; client cũ không bị ảnh hưởng.
- Rollback: bỏ UI/client registration rồi drop ba RPC/table bằng migration riêng;
  session đã thu hồi không phục hồi, người dùng đăng nhập lại.
- Tác động platform: stable installation UUID nằm trong SharedPreferences trên mọi
  platform và không được dùng làm authorization.

## Kế hoạch

- [x] Thêm schema/RPC và local/remote security contract.
- [x] Thêm client data/domain/BLoC/UI và regression test.
- [x] Generate DI, cập nhật tài liệu canonical và chạy full gate.
- [x] Backup production, apply migration, chạy remote contract và health probe.
- [ ] Commit, push, PR và xác minh default-branch CI.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| CI `master` run `29675120583` cho mốc trước | 7/7 pass | 2026-07-19 |
| `scripts/agent/check.sh full` | Final diff pass: docs/generated/format/analyze/platform/operations, 152/152 Flutter test và migration contract | 2026-07-19 |
| PostgreSQL ephemeral migration contract | Pass FORCE RLS/no direct access/self/cross-tenant/target revoke | 2026-07-19 |
| Production remote device registry contract | 25/25 pass; cleanup 0 user/0 orphan | 2026-07-19 |
| Backup trước migration | `supabase-20260719T060243Z`, local + encrypted off-host pass | 2026-07-19 |
| Backup/restore sau migration | `supabase-20260719T060755Z`, full rehearsal + encrypted off-host pass | 2026-07-19 |
| Production health | Systemd pass với active-session/device-registry probe | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] ADR

## Bàn giao

Chưa hoàn tất.
