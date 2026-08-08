# Task: Google Authenticator v2 interoperability

- Trạng thái: Hoàn thành trên Android AVD; còn physical Android/iOS
- Bắt đầu: 2026-07-27
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0015, ADR-0016

## Mục tiêu

Xác minh hai chiều với Google Authenticator current bằng runtime app-to-app, sửa
mọi mismatch schema/lifecycle tìm thấy và không giữ credential trong evidence.

## Ngoài phạm vi

- Công bố raw migration payload, TOTP secret hoặc mã OTP.
- Xem emulator là bằng chứng physical device.
- Thay đổi persisted vault, cloud snapshot hoặc Supabase contract.

## Acceptance criteria

- [x] Google Authenticator 7.2 → Hyper import thành công và TOTP match.
- [x] Hyper → Google Authenticator 7.2 import thành công và TOTP match.
- [x] Schema mới chỉ được mở rộng theo wire shape quan sát, vẫn bounded/fail closed.
- [x] Fresh OS auth không tạo QR trước lifecycle `resumed`.
- [x] Account, device PIN, raw payload, ảnh QR và file tạm được cleanup sau test.
- [ ] Lặp lại trên physical Android/iOS đại diện.

## Bằng chứng hiện tại

- Source path:
  `lib/features/authenticator/domain/services/google_authenticator_migration_parser.dart`
  và
  `lib/features/authenticator/presentation/pages/export_accounts_page.dart`.
- Cách tái hiện: Google Authenticator 7.2 trên Pixel AVD Android 17, local mode;
  Google → Hyper dùng Photo Picker, Hyper → Google dùng camera `imagefile:` của
  Android Emulator. Webcam/camera macOS không được dùng.
- Kết quả redacted: inbound là payload version 2 với một opaque OTP field 8;
  outbound version 1 được Google nhận; cả hai TOTP match expected.
- Test hiện có: reconstructed `TEST_ONLY` v1/v2 parser regressions và widget
  lifecycle resume/timeout.
- Giả định: field 8 là metadata opaque, không cần cho TOTP semantics hoặc local
  identity; parser validate bounded/non-empty rồi bỏ.

## Đánh giá rủi ro

- Lộ credential: chỉ giữ kết quả boolean/count; raw URI, secret, OTP, ảnh QR và
  UI dump nằm ở file tạm rồi cleanup.
- Mất dữ liệu local: vault ban đầu rỗng; import atomic; chỉ account test được xóa.
- Mất dữ liệu cloud: Google chạy local mode và Hyper không gọi sync/Supabase.
- Migration: không đổi persisted schema; v2 field 8 không được persist.
- Rollback: revert parser/lifecycle patch; vault không cần downgrade.
- Tác động platform: parser dùng chung; lifecycle fix áp dụng Android/iOS/macOS/
  Windows export. Physical-device evidence vẫn chưa có.

## Kế hoạch

- [x] Capture metadata shape redacted từ Google current.
- [x] Thêm regression thất bại trên parser version 1-only.
- [x] Hỗ trợ bounded version 2 field 8 và reject metadata khác.
- [x] Chạy Google → Hyper app-to-app.
- [x] Tái hiện/fix native-auth lifecycle race.
- [x] Chạy Hyper → Google bằng static emulator camera.
- [x] Cleanup toàn bộ test credential/artifact.
- [x] Chạy full quality gate.
- [ ] Xác nhận CI của PR.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Parser focused test | Pass 12 test | 2026-07-27 |
| Parser + export widget focused test | Pass 20 test | 2026-07-27 |
| `flutter analyze` | Pass, 0 diagnostic | 2026-07-27 |
| `scripts/agent/check.sh docs` | Pass, 52 file Markdown | 2026-07-27 |
| `scripts/agent/check.sh full` | Pass, gồm 225 Flutter test và backend/release/infra contract | 2026-07-27 |
| Google 7.2 → Hyper trên Android 17 AVD | Pass preview, atomic import và TOTP match | 2026-07-27 |
| Hyper → Google 7.2 trên Android 17 AVD | Pass scan/import và TOTP match | 2026-07-27 |
| Android device-credential prompt | Pass QR chỉ xuất hiện sau `resumed` | 2026-07-27 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `TESTING_STRATEGY.md`
- [x] `ROADMAP.md`
- [x] ADR-0015 và ADR-0016

## Bàn giao

Inbound parser nhận v1/v2 theo exact observed shape; exporter vẫn phát v1. Không
đổi data contract persisted hoặc Supabase. Gate còn lại là physical Android/iOS,
standard `otpauth` portability. Portable backup file từng được xem xét nhưng đã
bị loại bỏ theo ADR-0019.
