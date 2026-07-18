# Task: Mở kênh tải GitHub Preview

- Trạng thái: Hoàn tất
- Bắt đầu: 2026-07-19
- Owner: Hyperz
- Issue hoặc ADR liên quan: ADR-0010

## Mục tiêu

Người dùng tải được Windows x64 installer và Linux amd64 Debian package từ một
GitHub pre-release public, có checksum và provenance về tag/commit/CI.

## Ngoài phạm vi

- Phát hành Android, iOS, macOS hoặc qua app store.
- Tạo hoặc lưu signing certificate thay owner.
- Cấu hình SMTP production.
- Gọi unsigned preview là stable release.

## Acceptance criteria

- [x] Tag preview khớp package version và có tag CI pass toàn bộ.
- [x] Harness fail closed khi tag, confirmation, CI hoặc asset contract sai.
- [x] GitHub pre-release public có đúng Windows/Linux installer và checksum.
- [x] Public download được xác minh lại bằng SHA-256.
- [x] Canonical docs phân biệt preview unsigned với stable/store release.

## Bằng chứng hiện tại

- Source path: `.github/workflows/ci.yml`, `scripts/agent/package_*`.
- Cách tái hiện: CI tạo artifact theo commit với retention 14 ngày.
- Test hiện có: Linux distro/package transition; Windows installer transition;
  full quality/security gate.
- Giả định: repository tiếp tục public và Actions artifact của tag chưa hết hạn.

## Đánh giá rủi ro

- Lộ credential: thấp; release chỉ dùng artifact allowlist và public client config.
- Mất dữ liệu local: không đổi app/storage; package smoke đã kiểm tra retention.
- Mất dữ liệu cloud: không đổi schema hoặc sync contract.
- Migration: không có data migration mới.
- Rollback: xóa pre-release/asset, giữ source tag để audit; không xóa vault client.
- Tác động platform: chỉ Windows x64 và Linux amd64 được public ở giai đoạn này.

## Kế hoạch

- [x] Audit CI artifact và release hiện có.
- [x] Tạo release harness, asset validator và workflow thủ công.
- [x] Cập nhật canonical docs và ADR index.
- [x] Chạy full gate, commit và push branch.
- [x] Tạo tag, chờ tag CI pass, publish và verify public download.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Audit `gh release list`, tag và CI artifact | Chưa có release/tag; Windows/Linux artifact hiện có | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass: docs/generated/format/analyze/platform/release harness, 106 test và encrypted migration | 2026-07-19 |
| `scripts/agent/check_secrets.sh` | Pass toàn bộ 115 commit, không có leak | 2026-07-19 |
| GitHub Private Vulnerability Reporting API | `enabled=true` | 2026-07-19 |
| Branch CI `29656082645` tại `6c3bd4b` | Pass 7/7 | 2026-07-19 |
| Tag CI `29656402708` tại `v1.1.0-preview.1` | Pass 7/7 | 2026-07-19 |
| GitHub Release API/public download | Pre-release public, 5 asset; Windows/Linux SHA-256 khớp manifest | 2026-07-19 |
| PR `#1` → default branch | Merge commit `893b5be`; release/verification workflow đã có trên `master` | 2026-07-19 |
| Public verifier `29660968360` từ `master` | Pass exact tag commit/tag CI/5 asset/digest/checksum/manifest và Debian/PE32 signature | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SECURITY.md`
- [x] `DEPLOYMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] ADR

## Bàn giao

GitHub Preview đầu tiên đã public tại
`https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.0-preview.1`.
Không đổi local/cloud data contract. Windows/Linux artifact vẫn unsigned; SMTP,
stable signing, app store, physical-device và public legal/support gate được bảo
toàn trong roadmap. Không có thay đổi không liên quan trong working tree.
