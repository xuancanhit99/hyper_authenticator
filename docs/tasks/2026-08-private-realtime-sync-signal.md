# Task: Private Realtime wake-up cho account sync

- Trạng thái: Hoàn tất
- Bắt đầu: 2026-08-05
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0021

## Mục tiêu

Thiết bị đang foreground nhận thay đổi cloud từ thiết bị khác gần realtime mà
không truyền TOTP data qua WebSocket và không thay thế sync engine ADR-0020.

## Ngoài phạm vi

- Không hứa background delivery tức thời khi OS suspend app.
- Không dùng Postgres Changes hoặc mở direct table `SELECT`.
- Không truyền account payload/revision/Vault reference qua Broadcast.

## Acceptance criteria

- [x] Chỉ authenticated user join được private topic của chính mình.
- [x] Client không có quyền phát signal và anonymous không join được.
- [x] Insert/update/tombstone phát payload allowlist không chứa credential.
- [x] Signal/reconnect được debounce rồi gọi sync engine hiện có.
- [x] Logout/account switch hủy subscription cũ.
- [x] Realtime lỗi/mất event không phá resume/refresh/retry fallback.
- [x] Full gate, local migration và remote two-user contract pass.

## Bằng chứng hiện tại

- Source path: `lib/features/sync`, migration `20260804000000`.
- Cách tái hiện: thiết bị B foreground idle không nhận thay đổi từ A tới khi có
  resume/refresh/retry.
- Test hiện có: account-sync unit/migration/remote/iOS acceptance.
- Giả định đã xác minh: production Realtime 2.102.3 có
  `realtime.send(jsonb,text,text,boolean)` và `realtime.messages` RLS.

## Đánh giá rủi ro

- Lộ credential: giảm thiểu bằng signal không chứa account data.
- Mất dữ liệu local/cloud: Realtime không mutate trực tiếp; full sync là nguồn
  sự thật.
- Migration: additive policy/function/trigger, không rewrite account/Vault row.
- Rollback: drop trigger/function/policy; giữ nguyên RPC/data.
- Tác động platform: WebSocket foreground trên mọi platform, background tùy OS.

## Kế hoạch

- [x] Thêm migration private Broadcast và database contract test.
- [x] Thêm signal repository + lifecycle trong `SyncBloc`.
- [x] Thêm unit/remote/runtime test và docs canonical.
- [x] Chạy full gate, backup/deploy/remote verify production.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `scripts/agent/check.sh full` | Pass, 203/203 Flutter test | 2026-08-05 |
| `scripts/supabase/test_account_sync_migration.sh` | Pass, gồm authorization probe đúng Realtime 2.102.3 | 2026-08-05 |
| `scripts/supabase/test_remote_account_sync_contract.sh` | Pass 26/26, cleanup user/row/Vault fixture = 0 | 2026-08-05 |
| `scripts/agent/mobile_account_sync_operator.sh` trên iOS Simulator | Pass auth + remote-only upsert/delete qua Realtime | 2026-08-05 |
| iOS physical Ad Hoc `1.1.0 (13)` | Signature/secret scan/upgrade-install pass; device xác nhận build 13, auto-launch chờ unlock | 2026-08-05 |
| Backup/restore/off-host trước và sau migration | Pass với `supabase-20260805T154247Z` và `supabase-20260805T161016Z` | 2026-08-05 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] ADR

## Bàn giao

Production đã deploy migration gốc và corrective migration cho authorization
probe của Realtime 2.102.3. Remote contract, iOS Simulator runtime, health,
cleanup audit và hai mốc backup/restore/off-host đều pass. Android/Linux/Web
runtime và background delivery khi OS suspend vẫn là coverage tiếp theo, không
phải fallback data protocol mới.
