# Task: Tự động hóa restore drill định kỳ

- Trạng thái: Hoàn tất
- Bắt đầu: 2026-07-19
- Owner: Hyperz
- Issue hoặc ADR liên quan: Không cần ADR; không đổi trust boundary/data schema

## Mục tiêu

Biến restore rehearsal thủ công thành production gate định kỳ, fail-closed: chọn
backup hoàn chỉnh mới nhất, không chạy đồng thời với backup, restore vào database
tạm, xác minh security contract, luôn drop database tạm và chỉ publish evidence
sau khi toàn bộ drill pass.

## Ngoài phạm vi

- Restore đè production hoặc thay đổi data production.
- PITR/continuous WAL archive và dedicated off-host backup.
- External alert destination, SMTP hoặc release signing.
- Device registry hay thay đổi cryptographic contract E2EE.

## Acceptance criteria

- [x] Scheduled wrapper chọn exact backup mới nhất và từ chối backup quá hạn.
- [x] Backup và restore drill dùng cùng lock; không chạy đồng thời.
- [x] Evidence được ghi atomically, mode riêng tư, chỉ sau rehearsal thành công.
- [x] Lần pass còn mới được skip; failure không làm mới evidence và được retry.
- [x] Health gate fail khi evidence thiếu, sai format, ở tương lai hoặc quá hạn.
- [x] Systemd service/timer sandboxed, có resource priority và timeout hữu hạn.
- [x] Regression contract chạy được không cần Docker/credential/data thật.
- [x] Production drill dùng backup thật pass và database tạm được cleanup.

## Bằng chứng hiện tại

- Source path: `scripts/supabase/rehearse_backup_restore.sh`.
- Manual baseline: restore rehearsal ngày 18-07-2026 đã pass.
- Khoảng trống đã xác minh: chưa có scheduled automated restore drill.
- Giả định: production host giữ Docker access và backup root hiện tại.

## Đánh giá rủi ro

- Lộ credential: script không đọc/in server env; evidence chỉ có timestamp, tên
  backup và checksum manifest.
- Mất dữ liệu: chỉ tạo database tên `ha_restore_rehearsal_*`; trap force-drop,
  không nhận tên database production từ input.
- Availability: chạy off-hours với CPU/IO priority thấp; lock tránh cạnh tranh với
  backup; timeout systemd chặn job treo vô hạn.
- Rollback: disable timer và khôi phục health script/service cũ; backup/data không
  bị đổi hoặc xóa bởi wrapper.
- Tác động platform: chỉ production Supabase Linux host.

## Kế hoạch

- [x] Audit backup/restore harness, server timer và runbook hiện tại.
- [x] Chốt interval, freshness, locking và atomic evidence contract.
- [x] Implement wrapper, health validation, systemd unit và regression test.
- [x] Cập nhật operations/deployment/testing/project status.
- [x] Chạy full gate, production drill, commit/push và xác minh CI.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Audit `backup_production.sh`, `rehearse_backup_restore.sh`, health/systemd | Manual restore có security probe nhưng chưa schedule/evidence freshness | 2026-07-19 |
| `test_scheduled_restore_drill_contract.sh` | Pass due/skip/failure/stale/state-mode/systemd không Docker/credential | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass 50 docs, generated/format/analyze/platform/release/operations, 106 Flutter test và encrypted migration | 2026-07-19 |
| Production scheduled runner | Pass backup `supabase-20260718T100222Z`, full restore/security probe và atomic evidence | 2026-07-19 |
| Production post-probe | Health/timer success, evidence 0600 + manifest checksum match, 0 rehearsal database | 2026-07-19 |
| Production `systemd-analyze verify` | Pass; service result success, CPU/IO weight 25 | 2026-07-19 |
| CI `29658891453` tại `25967dbc7f2a4f1944776387cdff42573b06711a` | Pass 7/7: Quality, Secret, Android, Apple, Web, Linux và Windows | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] Operations runbook

## Bàn giao

Scheduled restore drill đã chạy production, health/timer active và implementation
pass CI 7/7. Không đổi client, encrypted snapshot, local vault hoặc production data
contract. Rollback copy của hai script cũ được giữ trên production host, ngoài
repository, để rollback vận hành có kiểm soát.
