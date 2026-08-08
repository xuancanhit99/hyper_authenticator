# Lịch sử rollout Supabase E2EE 2026-07

> **Đã bị thay thế bởi ADR-0020 account-managed sync.** File này
> chỉ ghi provenance lịch sử; không dùng command/schema trong Git revision cũ để
> dựng hoặc sửa production hiện tại.

## Bối cảnh lịch sử

Trong tháng 7 năm 2026, project từng rollout nhiều bước từ encrypted snapshot tới
active-session checks, device registry và per-device wrapping. Các bước đó có
backup, local/remote contract và restore evidence tại thời điểm triển khai.

Sau product/security audit, owner chọn xóa toàn bộ protocol phụ thay vì giữ
compatibility. Source hiện tại không còn device/session registry, per-device wrap,
key rotation hoặc portable encrypted file.

## Contract hiện tại

- ADR: [Minimal E2EE với một recovery path](../adr/0019-minimal-e2ee-single-recovery-path.md)
- Schema: `supabase/migrations/20260802000000_create_minimal_encrypted_vault.sql`
- Integration: [SUPABASE_INTEGRATION.md](../SUPABASE_INTEGRATION.md)
- Operations: [SUPABASE_PRODUCTION_OPERATIONS.md](SUPABASE_PRODUCTION_OPERATIONS.md)

## Rollback lịch sử

Backup lịch sử có thể chứa auth/system credential và encrypted user data. Chỉ
operator được ủy quyền mới được restore vào isolated, version-matched environment.
Không import object/protocol cũ vào Minimal E2EE database và không bật lại
plaintext/compatibility path.
