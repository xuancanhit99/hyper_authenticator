# Task: Phát hành GitHub Preview 7 sau failed tag Preview 6

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-08-09
- Owner: HyperZ
- Issue hoặc ADR liên quan: Không có; đây là rollout binary của contract hiện có

## Mục tiêu

Phát hành `v1.1.0-preview.7` từ đúng source account-managed automatic sync, kèm
Android APK đã ký và các package Windows/Linux do tag CI tạo, có checksum,
provenance và public verification tái hiện được.

## Ngoài phạm vi

- Không phát hành App Store, TestFlight, Play Store hoặc stable release.
- Không đính kèm iOS/macOS binary vào GitHub Preview này.
- Không thay đổi data contract local, Supabase schema hoặc signing key.

## Acceptance criteria

- [x] Package version canonical là `1.1.0+14` và tag trỏ đúng commit đã merge.
- [x] Full gate pass trên release candidate.
- [x] Tag CI pass và tạo đúng Android/Windows/Linux artifact từ cùng commit.
- [x] Public pre-release có đúng bảy asset, checksum và signer pin hợp lệ.
- [x] Release notes ghi rõ server-managed encryption và các giới hạn còn lại.

## Bằng chứng hiện tại

- Source path: `.github/workflows/ci.yml`, `scripts/agent/github_preview_release.sh`.
- Cách tái hiện: tag push tạo signed APK và package desktop; publisher chỉ nhận
  artifact từ successful tag CI.
- Test hiện có: release/infra harness trong `scripts/agent/check.sh full`.
- Giả định: GitHub Actions variables và bốn Android signing secrets vẫn được cấu
  hình; artifact signer phải khớp `android/app-signing-certificate.sha256`.

## Đánh giá rủi ro

- Lộ credential: tag CI chỉ nhận public runtime config và keystore qua encrypted
  secret; public verifier từ chối env/debug artifact.
- Mất dữ liệu local: release không mutate vault; upgrade vẫn cần người dùng giữ
  cùng Android signer để cài đè.
- Mất dữ liệu cloud: không migration; client này yêu cầu production backend đã
  chạy ADR-0020/ADR-0021.
- Migration: không có.
- Rollback: chuyển release lỗi về draft; người dùng có thể quay lại local-only,
  nhưng APK signer/version vẫn chi phối khả năng downgrade của Android.
- Tác động platform: Android signed; Windows/Linux vẫn unsigned Preview; iOS và
  macOS không có asset.

## Kế hoạch

- [x] Chuẩn hóa version và test fixture release.
- [x] Chạy full gate, review và merge release candidate.
- [x] Tạo/push tag rồi chờ exact tag CI pass.
- [x] Publish bằng release harness và public-verify toàn bộ asset.
- [x] Ghi lại evidence sau publish trong tài liệu canonical.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| APK local `1.1.0+14` signer pin + metadata | Pass trước release candidate | 2026-08-09 |
| `scripts/agent/check.sh full` | Pass: 203 Flutter test và toàn bộ backend/release/infra gate | 2026-08-09 |
| Backend gate sau khi đợi final postmaster PID 1 | Pass; loại bỏ race với initdb server tạm | 2026-08-09 |
| PR #35 Windows local-vault smoke | Pass sau fix đầu nhưng tag Preview 6 tái hiện selector chọn nhầm ListView ẩn | 2026-08-09 |
| Tag `v1.1.0-preview.6` | Failed CI, không tạo GitHub Release; giữ tag làm evidence bất biến | 2026-08-09 |
| Fix Preview 7 vòng 1 | Chọn đúng Scrollable ancestor nhưng live Windows vẫn trả hit-testable rỗng | 2026-08-09 |
| Fix Preview 7 vòng 2 | Center submit bằng ensureVisible; tap thật rồi dùng UI/vault outcome làm acceptance | 2026-08-09 |
| Root cause UI | Submit ở cuối ListView có 0px bottom clearance; live Windows đặt tâm nút tại y=632/640 | 2026-08-09 |
| Fix Preview 7 vòng 3 | Thêm 64px + safe-area trailing padding và regression khóa clearance >=48px | 2026-08-09 |
| Fix Preview 7 vòng 4 | Linux/Windows xác nhận animated `ensureVisible` deadlock khi Future chờ pump; đổi sang jump đồng bộ + một frame có giới hạn, đồng thời tránh `pumpAndSettle()` với TOTP countdown | 2026-08-09 |
| PR #36 | CI run `31277597553` pass toàn bộ; merge commit `feec221101ab40aa9cd89d5e151265bd901ca255` | 2026-08-09 |
| Tag `v1.1.0-preview.7` | Exact tag CI run `31278011636` pass toàn bộ và tạo artifact từ cùng commit | 2026-08-09 |
| Public release harness | Pass: đúng 7 asset; GitHub digest, checksum/manifest, Android signer pin, Debian và Windows PE32 hợp lệ | 2026-08-09 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `DEPLOYMENT.md`
- [x] `README.md`
- [x] Tài liệu data/security khác không đổi vì không đổi hành vi hoặc contract

## Bàn giao

- Kết quả: [`v1.1.0-preview.7`](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.0-preview.7)
  đã là public pre-release, không phải draft.
- Data contract: không đổi local vault, Supabase schema hoặc sync protocol.
- Binary contract: Android APK đã ký; Windows/Linux chưa code-sign; iOS/macOS
  không có trong release này.
- Rollback: nếu phát hiện lỗi lớn, chuyển release về draft; không xóa/rewrite tag
  vì provenance đã công khai.
- Theo dõi còn lại: store signing/notarization, physical acceptance rộng hơn,
  SMTP và public privacy/support/alert inputs vẫn là gate về sau.
