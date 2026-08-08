# Task: Export Google Authenticator an toàn

- Trạng thái: Hoàn thành source và Android AVD app-to-app; còn physical gate riêng
- Bắt đầu: 2026-07-27
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0016

## Mục tiêu

Người dùng chọn nhiều tài khoản TOTP, xác thực lại bằng cơ chế hệ điều hành và
quét một hoặc nhiều QR migration bằng Google Authenticator mà không mutate vault.

## Ngoài phạm vi

- Portable backup file (sau đó đã bị ADR-0019 loại bỏ) và export `otpauth` độc lập.
- HOTP hoặc TOTP có period khác 30 giây.
- Khẳng định physical-device interoperability từ evidence Android AVD.

## Acceptance criteria

- [x] Chỉ tạo QR sau fresh OS reauthentication.
- [x] QR có cảnh báo credential exposure, timeout 60 giây và bị xóa khi app nền.
- [x] Multi-part round-trip qua parser version 1 giữ issuer/name/algorithm/digits.
- [x] Secret/full URI không xuất hiện trong log representation hoặc semantics.
- [x] Cancel, auth lỗi hoặc dữ liệu không biểu diễn được không mutate vault.
- [x] Google Authenticator 7.2 trên Android AVD nhận QR v1 và tạo cùng TOTP.
- [x] Native auth success chỉ tạo QR sau lifecycle trở lại `resumed`.

## Bằng chứng hiện tại

- Source path: `lib/features/authenticator/domain/services/`
- Baseline trước thay đổi: account list không có action export.
- Test nền: parser reconstructed fixture và import atomic.
- Evidence: Google Authenticator 7.2 trên Android 17 AVD nhận migration v1 do
  Hyper tạo; TOTP match được kiểm tra dạng boolean/redacted.
- Giả định: physical Android/iOS vẫn là gate độc lập.

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
| Android AVD + Google Authenticator 7.2 | Pass Hyper v1 → Google; TOTP match; test account/file tạm đã cleanup | 2026-07-27 |
| Android AVD device credential | Pass fresh auth → lifecycle resumed → QR; timeout không resumed fail closed | 2026-07-27 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `TESTING_STRATEGY.md`
- [x] `PRIVACY_POLICY.md`
- [x] ADR

## Bàn giao

Source P0 export và app-to-app Android AVD đã hoàn tất mà không đổi persisted data
contract. Physical Hyper → Google trên Android/iOS current vẫn phải chạy riêng
trước stable release.
