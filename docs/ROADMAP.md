# Roadmap

Roadmap được ưu tiên theo rủi ro, không phải cam kết thời gian.

## Giai đoạn 0 — Baseline đáng tin cậy

- [x] Chuyển `.env` khỏi Flutter asset sang build-time define.
- [x] Thay template test bằng unit test thật.
- [x] Analyzer/format sạch và deprecated API chính được cập nhật.
- [x] CI pin Flutter và build sáu platform cùng Web.
- [x] Nâng direct dependency và native toolchain.
- [x] Thống nhất display name Hyper Authenticator.
- [ ] Chọn và thêm license.
- [ ] Thêm Supabase schema/RLS migration được version control.

Exit criteria còn lại: schema/RLS gate deterministic và license rõ ràng.

## Giai đoạn 1 — Tính đúng đắn local

- [x] Giữ algorithm, digits và period khi create/restore.
- [x] Validate URI, Base32, algorithm, digits và period.
- [x] Xóa log chứa QR secret.
- [x] Logout không xóa TOTP local.
- [x] App-lock error fail closed và relock theo lifecycle.
- [ ] Countdown theo period từng account.
- [ ] Recovery cho secure-storage record/index.
- [ ] BLoC/widget/device integration coverage.
- [ ] Quyết định ownership khi nhiều Supabase user dùng cùng thiết bị.

Exit criteria: TOTP, persistence và lock có regression/integration coverage trên platform chính.

## Giai đoạn 2 — Thiết kế lại sync

- [x] UI và sync dùng chung account-state owner.
- [x] Partial merge failure dừng upload.
- [ ] ADR cho identity, deletion, conflict, concurrency và atomic publication.
- [ ] Thay xóa-rồi-chèn bằng protocol atomic/idempotent.
- [ ] Tombstone hoặc revisioned snapshot.
- [ ] Interrupted write/retry/two-device tests.

Exit criteria: network hoặc concurrency failure không làm mất snapshot hợp lệ gần nhất.

## Giai đoạn 3 — E2EE

- [ ] ADR key hierarchy/recovery.
- [ ] Authenticated encryption có version.
- [ ] Onboarding đa thiết bị và recovery.
- [ ] Migration row plaintext.
- [ ] Chứng minh backend chỉ thấy ciphertext.

Exit criteria: backend-blind secret storage được test và review.

## Giai đoạn 4 — Auth và product flow

- [ ] Quyết định offline-only.
- [ ] Chọn recovery surface, hoàn thiện deep link và test.
- [ ] Data export/deletion/retention hướng tới user.
- [ ] Localization đầy đủ và accessibility baseline.

Exit criteria: behavior, privacy policy và store declaration khớp nhau.

## Giai đoạn 5 — Platform release

- [x] Android/macOS/Web build trên baseline local.
- [x] CI build iOS/Windows/Linux.
- [ ] Xác minh iOS trên runtime/thiết bị và TestFlight.
- [ ] Android production signing/Play checks.
- [ ] macOS signing/notarization.
- [ ] Windows/Linux installer, signing và device test.
- [ ] Web threat model/header/deployment hardening.
- [ ] Release provenance, rollback và incident process.

Exit criteria: gate trong `DEPLOYMENT.md` pass riêng cho từng platform được quảng bá.

## Quy tắc chọn việc

Ưu tiên blocker làm lộ credential hoặc mất dữ liệu trước convenience feature, trừ khi owner chấp nhận rủi ro rõ ràng. Mỗi hạng mục lớn dùng `docs/tasks/TEMPLATE.md` và ghi bằng chứng xác minh.
