# Task: Account-managed automatic TOTP sync

- Trạng thái: Hoàn tất source, production rollout và iOS acceptance
- Bắt đầu: 2026-08-04
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0020

## Mục tiêu

Người dùng không đăng nhập vẫn dùng local; sau đăng nhập, mã tự tải lên/xuống và
thao tác xóa được truyền tới cloud/thiết bị khác mà không cần recovery key.

## Ngoài phạm vi

- Không giả lập toàn bộ UI/quản lý nhiều Google Account của Google Authenticator.
- Không thêm device/session registry, key rotation hoặc compatibility fallback.
- Không deploy breaking production migration trước backup/audit cuối.

## Acceptance criteria

- [x] Không còn recovery key, setup E2EE hoặc conflict resolution trong UI/source.
- [x] Sign-in/session restore tự kích hoạt sync; sign-out giữ local và dừng sync.
- [x] Add/update/import khi đăng nhập tự upload; lỗi mạng không rollback local.
- [x] Delete khi đăng nhập tạo tombstone và thiết bị khác xóa local sau sync.
- [x] Thiết bị mới đăng nhập tải mã cloud mà không cần secret bổ sung.
- [x] Account thuộc user A không tự upload sang user B.
- [x] Database chỉ lưu Vault ciphertext và RLS/RPC chặn cross-user access.
- [x] Full gate và database contract test pass.

## Bằng chứng hiện tại

- Source path: `lib/features/sync`, `lib/features/settings/presentation/pages/settings_page.dart`
- UI mới: Settings hiển thị trạng thái “Đồng bộ với tài khoản”; không còn chuỗi
  hoặc route setup/import recovery key.
- Runtime: iOS Simulator pass UI auth, giữ local vault, upload, new-device
  download và tombstone với isolated production user.
- Product decision: owner chấp nhận server-managed encryption để đổi lấy sign-in
  recovery không cần key theo ADR-0020.

## Đánh giá rủi ro

- Lộ credential: backend có quyền giải mã; giảm thiểu bằng Vault, auth RPC và ACL.
- Mất dữ liệu local: cloud failure không được rollback local mutation.
- Mất dữ liệu cloud: breaking migration cần backup và xác nhận snapshot hiện tại.
- Migration: không thể chuyển HA1 ciphertext nếu không có user-held key.
- Rollback: client có thể về local-only; backend cần full backup + Vault root key.
- Tác động platform: auto sync dự kiến dùng chung Android/iOS/macOS/Web/Windows/Linux.

## Kế hoạch

- [x] Thay Minimal E2EE domain/data bằng per-account RPC và local sync metadata.
- [x] Nối sync với auth lifecycle và account mutations.
- [x] Đơn giản hóa Settings thành trạng thái đồng bộ tự động.
- [x] Thêm migration/RLS/RPC tests và xóa protocol cũ.
- [x] Cập nhật tài liệu canonical và chạy full gate.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `scripts/agent/check.sh full` | Pass: 200 Flutter test và mọi gate | 2026-08-04 |
| `scripts/supabase/test_account_sync_migration.sh` | Pass trên image production | 2026-08-04 |
| `scripts/supabase/test_remote_account_sync_contract.sh` | Pass 25/25 production | 2026-08-04 |
| `scripts/agent/mobile_account_sync_operator.sh` | Pass iOS Simulator, cleanup verified | 2026-08-04 |
| iOS Ad Hoc upgrade/install/launch | Pass `1.1.0 (12)` trên iPhone 16 Pro | 2026-08-04 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] ADR

## Bàn giao

Đã hoàn tất implementation, breaking production rollout có backup/rehearsal và
iOS acceptance. Android/Linux/Web runtime cùng independent security review là
release-hardening tiếp theo, không chặn contract ADR-0020 hiện tại.
