# Task: Tự động xác minh public release channel

- Trạng thái: Hoàn tất
- Bắt đầu: 2026-07-19
- Owner: Hyperz
- Issue hoặc ADR liên quan: ADR-0010

## Mục tiêu

Mọi GitHub Preview mới chỉ được xem là publish thành công khi một client không
đăng nhập tải được exact asset allowlist và xác minh tag, commit, successful tag
CI, GitHub digest, individual checksum, manifest tổng cùng file signature.

## Ngoài phạm vi

- Code signing, notarization hoặc app store.
- SMTP, support mailbox hoặc alert destination.
- Thay đổi app, local vault, cloud schema hay E2EE data contract.
- Thực thi unsigned installer trên thiết bị người dùng.

## Acceptance criteria

- [x] Verifier không gửi Authorization và fail nếu release không public/pre-release.
- [x] Exact tag/commit/tag-CI provenance được xác minh qua public GitHub API.
- [x] Exact năm asset được tải public và khớp API digest/checksum/manifest.
- [x] Publisher chuyển release lỗi về draft thay vì để public trạng thái mơ hồ.
- [x] Release workflow có post-publish/manual verification gate.
- [x] Verifier pass trên `v1.1.0-preview.1` hiện tại.

## Bằng chứng hiện tại

- Source path: `scripts/agent/github_preview_release.sh`, GitHub Release API.
- Cách tái hiện: public download/checksum hiện mới được chạy thủ công sau release.
- Test hiện có: asset validator có success và fail-closed fixture; tag CI 7/7.
- Giả định: repository và release tiếp tục public.

## Đánh giá rủi ro

- Lộ credential: verifier cố ý không nhận hoặc gửi GitHub token.
- Mất dữ liệu local/cloud: không chạy app và không đổi storage/backend.
- Migration: không có.
- Rollback: publisher chuyển release lỗi thành draft; tag/source được giữ để audit.
- Tác động platform: chỉ đọc metadata/download Windows/Linux public asset.

## Kế hoạch

- [x] Audit khoảng trống giữa CI artifact và public release channel.
- [x] Thêm public metadata/provenance/digest/checksum verifier.
- [x] Gắn verifier vào publisher và workflow post-publish/manual.
- [x] Thêm canonical offline contract test cho syntax, invalid input,
  no-Authorization và draft rollback.
- [x] Chạy verifier với release thật và cập nhật canonical docs.
- [x] Chạy full gate, commit/push và xác minh CI.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `verify_github_preview_release.sh v1.1.0-preview.1 ... 6c3bd4b...` | Pass public release/commit/run `29656402708`, 5 asset, digest/checksum/signature | 2026-07-19 |
| Verifier với expected commit toàn số 0 | Fail closed: tag commit mismatch | 2026-07-19 |
| Verifier với tag stable `v1.1.0` | Fail closed: tag format không hợp lệ | 2026-07-19 |
| Asset validator với historical package version override | Pass; verifier không phụ thuộc current `pubspec.yaml` | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass docs/generated/format/analyze/platform/offline release contract, 106 Flutter test và encrypted migration | 2026-07-19 |
| CI `29657661620` Quality lần đầu | Fail sau app test/migration: Ubuntu runner không có `rg`; thêm deterministic `grep` fallback | 2026-07-19 |
| CI `29657820675` tại `7791487ee72529ade3301a7bee03736e3393ae27` | Pass 7/7: Quality, Secret, Android, Apple, Web, Linux và Windows | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SECURITY.md`
- [x] `DEPLOYMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] ADR không đổi; implementation làm chặt gate đã chấp nhận trong ADR-0010

## Bàn giao

Public release verifier đã được live-test với `v1.1.0-preview.1`; implementation
và fallback không phụ thuộc `rg` đã pass CI 7/7. Không đổi app hoặc data contract.
Workflow post-publish chỉ bắt đầu tự chạy sau khi được merge vào default branch.
Signing, SMTP, device thật, alert destination và backup host độc lập vẫn là
follow-up.
