# Task: Khôi phục provider logo catalog có provenance

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-08-10
- Owner: xuancanhit99
- Issue hoặc ADR liên quan: ADR-0007, ADR-0023

## Mục tiêu

Tự động hiển thị logo dịch vụ cho mã TOTP đã nhận diện, dùng snapshot Sentinel
Icons mới đã pin và có license/integrity evidence; provider không nhận diện vẫn
hiển thị avatar chữ cái an toàn.

## Ngoài phạm vi

- Không lưu logo/provider ID vào account hoặc cloud payload.
- Không khôi phục dialog chọn logo từng thay đổi trực tiếp giá trị issuer.
- Không tải logo từ Internet trong runtime.

## Acceptance criteria

- [x] Logo Google và provider mới như Vercel được resolve từ issuer.
- [x] Issuer không có logo và mapping lỗi vẫn fallback, không chặn TOTP.
- [x] Catalog có source commit, MIT License, checksum và integrity gate.
- [x] Main app và Chrome Extension chỉ dùng asset local.
- [x] Full gate pass và artifact build không yêu cầu network runtime.

## Bằng chứng hiện tại

- Source path: `lib/features/authenticator/presentation/widgets/account_avatar.dart`.
- Cách tái hiện: account hiện chỉ render ký tự đầu của issuer.
- Test hiện có: chưa có test riêng cho provider logo.
- Giả định: owner duyệt khôi phục catalog ngày 2026-08-10.

## Đánh giá rủi ro

- Lộ credential: không; resolver chỉ đọc issuer vốn đã render trên UI, không log.
- Mất dữ liệu local/cloud: không đổi persisted contract.
- Migration: không có.
- Rollback: bỏ catalog/bootstrap và quay lại avatar ký tự.
- Tác động platform: tăng artifact khoảng 28,5 MB raw; mọi target và extension.

## Kế hoạch

- [x] Pin/import upstream cùng provenance và integrity harness.
- [x] Tích hợp resolver + fallback và LicensePage.
- [x] Thêm test resolver/widget/catalog.
- [x] Cập nhật canonical docs và chạy full gate/build smoke.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `scripts/agent/check_provider_logo_catalog.sh` | Pass: 1.076 asset, 1.201 issuer/alias; checksum/payload/unresolved allowlist đúng | 2026-08-10 |
| Provider catalog/avatar/license test | Pass: 11 regression test | 2026-08-10 |
| `scripts/agent/check.sh full` | Pass: docs/codegen/format/analyze/platform, 242 Flutter test, backend/release/infra | 2026-08-10 |
| `scripts/agent/build_chrome_extension.sh` | Pass package verifier; ZIP 42.460.896 byte, đủ 1.076 logo + MIT License | 2026-08-10 |
| `scripts/agent/check_secrets.sh` | Pass, không phát hiện leak | 2026-08-10 |

Package source được nâng thành `1.1.3+17`; GitHub Preview dự kiến là
`v1.1.3-preview.1`. Trạng thái public chỉ được cập nhật sau exact-tag CI và
public verifier, không suy ra từ việc build local.

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `DEVELOPMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] ADR

## Bàn giao

Catalog mới đã được tích hợp tự động vào `AccountAvatar` trên app/extension; không
đổi data contract và fallback avatar ký tự. Rủi ro còn lại là artifact tăng kích
thước và trademark/provenance từng brand mark chưa có chứng từ riêng ngoài MIT
repository-level; xem ADR-0023 và `PROJECT_STATUS.md`.
