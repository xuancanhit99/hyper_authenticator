# Task: Portability chuẩn otpauth

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-07-27
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0017

## Mục tiêu

Cho phép import và export TOTP bằng QR `otpauth://totp` phổ biến, giữ nguyên
issuer, account name, secret, algorithm, digits và period qua round-trip mà không
tạo thêm đường lộ credential ngoài protected export boundary hiện có.

## Ngoài phạm vi

- HOTP, proprietary push MFA hoặc password-manager backup format.
- Gộp nhiều account vào một QR `otpauth`; mỗi QR chuẩn chứa một account.
- Encrypted backup file; đây là P0 kế tiếp sau task này.

## Acceptance criteria

- [x] Parser/exporter round-trip đầy đủ TOTP semantics và reject payload lỗi.
- [x] Standard QR import luôn preview trước atomic append; cancel không mutate.
- [x] Exact duplicate được bỏ qua qua import use case hiện có.
- [x] Export nhiều account thành một chuỗi QR, mỗi QR là một URI standard.
- [x] Export yêu cầu fresh OS auth, timeout và lifecycle cleanup như Google flow.
- [x] Full URI/secret không xuất hiện trong log, semantics, BLoC hoặc route.
- [x] Không đổi persisted vault, encrypted snapshot hoặc Supabase contract.

## Bằng chứng hiện tại

- Source path: `totp_uri_parser.dart`, `totp_uri_exporter.dart`,
  `add_account_page.dart`, `totp_import_preview_dialog.dart` và
  `export_accounts_page.dart`.
- Scanner đã chuyển từ single-account add trực tiếp sang preview rồi atomic import.
- Focused regression đã pass 33 test cho parser/exporter, preview
  confirm/cancel, protected export/lifecycle và local-auth reason.
- Standard `otpauth` không có multi-account container; UI hiển thị lần lượt một
  QR cho mỗi account.

## Đánh giá rủi ro

- Lộ credential: QR và URI chứa raw TOTP secret; chỉ được tạo sau fresh auth và
  giữ trong widget memory.
- Mất dữ liệu local: import dùng validate-all + atomic COW append; không replace.
- Mất dữ liệu cloud: task không gọi sync hoặc Supabase.
- Migration: không đổi persisted schema.
- Rollback: revert parser/exporter/UI; vault không cần downgrade.
- Tác động platform: import theo capability camera/image hiện có; export chỉ trên
  Android/iOS/macOS/Windows có OS authentication boundary.

## Kế hoạch

- [x] Thêm failing regression cho standard import preview/cancel.
- [x] Thêm bounded standard URI exporter và round-trip test.
- [x] Dùng chung protected multi-format export page.
- [x] Generalize preview dialog mà không lộ secret.
- [x] Cập nhật canonical docs và ADR.
- [x] Chạy focused/full gate và platform build evidence.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Focused Flutter test: parser/exporter/import/export/local-auth | Pass, 33 test | 2026-07-27 |
| `flutter analyze` | Pass, 0 diagnostic | 2026-07-27 |
| `scripts/agent/check.sh full` | Pass, gồm 234 Flutter test và backend/release/infra contract | 2026-07-27 |
| `flutter build apk --debug` | Pass; tạo local-only debug APK | 2026-07-27 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `TESTING_STRATEGY.md`
- [x] `ROADMAP.md`
- [x] ADR-0017

## Bàn giao

Standard QR import hiện luôn preview rồi atomic append/exact-dedupe; export tạo
một QR/account trong cùng fresh-auth/timeout/lifecycle boundary với Google
transfer. Parser/exporter giữ issuer, account name, algorithm, digits và period
qua round-trip. Không đổi persisted vault, encrypted snapshot, Supabase
schema/RPC hoặc production data.

Android debug compile là platform evidence của change set. Gate còn lại là
app-to-app interoperability trên physical Android/iOS; không được lưu raw
payload, secret hoặc OTP vào evidence. Encrypted backup file là P0 tiếp theo và
phải có task/threat model riêng.
