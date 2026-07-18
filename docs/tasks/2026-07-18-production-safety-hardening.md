# Task: Hardening dữ liệu và đường phát hành trước production

- Trạng thái: Hoàn tất batch an toàn; chờ quyết định kiến trúc tiếp theo
- Bắt đầu: 2026-07-18
- Owner: canhvx
- Issue hoặc ADR liên quan: `docs/E2EE_DESIGN.md`; ADR về local vault, sync v2 và E2EE sẽ được tách riêng

## Mục tiêu

Loại bỏ các failure mode có thể làm lộ TOTP credential, mất dữ liệu local/cloud
hoặc tạo artifact phát hành không an toàn trước khi thiết kế E2EE cuối cùng được
owner chấp nhận.

## Ngoài phạm vi

- Không tự quyết định license của sản phẩm.
- Không tự chọn recovery model/key hierarchy E2EE khi chưa có owner decision.
- Không deploy migration phá hủy hoặc bật dịch vụ mới trên host production.

## Acceptance criteria

- [x] Plaintext cloud sync bị khóa mặc định và không thể vô tình bật trong release.
- [x] Recovery web không log session, không copy `.env` vào image và nhận public config an toàn.
- [x] Android release build không fallback sang debug signing.
- [x] Countdown phản ánh đúng `period` của từng account.
- [x] Local storage chịu được partial write, concurrent mutation và record/index hỏng có kiểm soát.
- [x] Merge giữ stable account ID và không báo success trước khi persistence hoàn tất.
- [x] Full quality gate cùng build bị tác động pass.

## Bằng chứng hiện tại

- Source path: `lib/features/sync`, `lib/features/authenticator`,
  `reset-password-web`, `android/app/build.gradle.kts`.
- Cách tái hiện: xem release blocker trong `docs/PROJECT_STATUS.md`.
- Test hiện có: 12 unit test cùng Supabase remote contract test đã ghi nhận.
- Giả định: instance Supabase mới chưa chứa application data thật theo baseline
  ngày 2026-07-17; mọi thay đổi remote destructive vẫn cần xác minh lại trước deploy.

## Đánh giá rủi ro

- Lộ credential: cao nếu plaintext sync hoặc recovery-session logging được bật.
- Mất dữ liệu local: cao khi record/index write bị gián đoạn.
- Mất dữ liệu cloud: critical với flow delete-rồi-insert hiện tại.
- Migration: local storage cần dual-read/write-verify-commit; remote schema chưa đổi
  trước khi E2EE decision được chấp nhận.
- Rollback: giữ legacy local keys và generation hợp lệ trước; cloud sync bị khóa
  thay vì thay đổi destructive schema.
- Tác động platform: local secure storage cần test trên native; Web giữ threat model riêng.

## Kế hoạch

- [x] Thêm guard plaintext cloud sync và release signing fail-closed.
- [x] Harden recovery web.
- [x] Sửa countdown và test period tùy chỉnh.
- [x] Triển khai local storage versioned copy-on-write và recovery test.
- [x] Refactor merge/sync orchestration trong phạm vi không cần quyết định conflict mới.
- [x] Cập nhật tài liệu canonical và chạy full gate/build khả dụng trên host.
- [ ] Trình owner các quyết định E2EE recovery, vault ownership và license.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `scripts/agent/check.sh full` | Pass: docs/generated/format/analyze và 28 Flutter test | 2026-07-18 |
| Focused Flutter regression suite | 16 pass | 2026-07-18 |
| `reset-password-web/test.sh` | Pass, gồm image/config/header/no-log | 2026-07-18 |
| `scripts/agent/build.sh host` | Pass: Android debug, Web release, macOS debug | 2026-07-18 |
| Android `flutter build appbundle --release` không có key | Fail đúng chủ đích tại signing gate | 2026-07-18 |
| `scripts/agent/build.sh ios` | Bị chặn: host thiếu iOS 26.5 Simulator Runtime | 2026-07-18 |
| `flutter pub outdated` / `flutter pub upgrade` | Direct dependency mới nhất; nâng transitive passkeys 2.9.0 | 2026-07-18 |
| `scripts/agent/check.sh docs` sau khi sửa worktree filter | Pass, thực sự quét 31 Markdown file | 2026-07-18 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] ADR-0002 cho local storage v2

## Bàn giao

- Cloud sync plaintext fail closed ở release; remote schema/data không bị thay đổi
  trong batch này.
- Local storage tự migrate sang v2 copy-on-write và giữ nguyên legacy keys để
  rollback; chưa có compaction nên storage có thể tăng theo số mutation.
- Merge giữ stable ID nhưng protocol cloud vẫn thiếu revision/tombstone/atomic
  publication; do đó release sync tiếp tục bị khóa.
- Recovery Web đã harden nhưng chưa nối email-template E2E do cần chọn canonical
  recovery surface.
- Các quyết định còn mở: local vault ownership/offline-first, recovery surface,
  E2EE key recovery và license.
