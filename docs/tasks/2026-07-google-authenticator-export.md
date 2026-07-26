# Task: Export Google Authenticator an toàn

- Trạng thái: Hoàn thành source; còn physical interoperability gate riêng
- Bắt đầu: 2026-07-27
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0016

## Mục tiêu

Người dùng chọn nhiều tài khoản TOTP, xác thực lại bằng cơ chế hệ điều hành và
quét một hoặc nhiều QR migration bằng Google Authenticator mà không mutate vault.

## Ngoài phạm vi

- Encrypted backup file và export `otpauth` độc lập.
- HOTP hoặc TOTP có period khác 30 giây.
- Khẳng định physical interoperability trước khi có test app-to-app thật.

## Acceptance criteria

- [x] Chỉ tạo QR sau fresh OS reauthentication.
- [x] QR có cảnh báo credential exposure, timeout 60 giây và bị xóa khi app nền.
- [x] Multi-part round-trip qua parser version 1 giữ issuer/name/algorithm/digits.
- [x] Secret/full URI không xuất hiện trong log representation hoặc semantics.
- [x] Cancel, auth lỗi hoặc dữ liệu không biểu diễn được không mutate vault.

## Bằng chứng hiện tại

- Source path: `lib/features/authenticator/domain/services/`
- Baseline trước thay đổi: account list không có action export.
- Test nền: parser reconstructed fixture và import atomic.
- Giả định: Google migration schema version 1 tiếp tục tương thích với field TOTP
  đã tái dựng; physical test vẫn là gate độc lập.

## Đánh giá rủi ro

- Lộ credential: QR là raw TOTP credential; cần auth, warning, timeout, lifecycle
  cleanup và redacted diagnostics.
- Mất dữ liệu local: không ghi vault.
- Mất dữ liệu cloud: không gọi sync/Supabase.
- Migration: không đổi persisted schema.
- Rollback: revert UI/encoder; data không cần downgrade.
- Tác động platform: Android/iOS/macOS/Windows; Web/Linux fail closed vì chưa có
  OS reauthentication boundary.

## Kế hoạch

- [x] Audit app-lock và Google migration parser.
- [x] Thêm bounded encoder + round-trip regression.
- [x] Thêm fresh-auth service và export UI.
- [x] Cập nhật ADR/tài liệu canonical.
- [x] Chạy full gate và platform build smoke.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Focused exporter/auth/widget/account tests | Pass, 16 test | 2026-07-27 |
| `flutter analyze` | Pass, 0 diagnostic | 2026-07-27 |
| `scripts/agent/check.sh full` | Pass, gồm 220 Flutter test và backend/release/infra contract | 2026-07-27 |
| `scripts/agent/build.sh host` | Pass Android debug, Web release, macOS unsigned compile | 2026-07-27 |
| `scripts/agent/build.sh ios` | Pass iOS Simulator debug compile | 2026-07-27 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `TESTING_STRATEGY.md`
- [x] `PRIVACY_POLICY.md`
- [x] ADR

## Bàn giao

Source P0 export đã hoàn tất mà không đổi data contract persisted. Physical
Hyper → Google trên Android/iOS current vẫn phải chạy riêng trước khi coi format
reconstructed là evidence app-to-app hoặc đưa feature vào stable release.
