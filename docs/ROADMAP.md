# Roadmap

Roadmap được ưu tiên theo rủi ro, không phải cam kết thời gian.

## Giai đoạn 0 — Baseline đáng tin cậy

- [x] Chuyển `.env` khỏi Flutter asset sang build-time define.
- [x] Thay template test bằng unit test thật.
- [x] Analyzer/format sạch và deprecated API chính được cập nhật.
- [x] CI pin Flutter và build sáu platform cùng Web.
- [x] Nâng direct dependency và native toolchain.
- [x] Thống nhất display name Hyper Authenticator.
- [x] Chọn và thêm Apache License 2.0.
- [x] Thêm Supabase schema/RLS migration và cross-user contract test được version control.

Exit criteria còn lại: license rõ ràng; remote contract gate cần ephemeral CI
environment trước khi tự động hóa hoàn toàn.

## Giai đoạn 1 — Tính đúng đắn local

- [x] Giữ algorithm, digits và period khi create/restore.
- [x] Validate URI, Base32, algorithm, digits và period.
- [x] Xóa log chứa QR secret.
- [x] Logout không xóa TOTP local.
- [x] App-lock error fail closed và relock theo lifecycle.
- [x] Countdown theo period từng account.
- [x] Recovery cho secure-storage record/index bằng generation copy-on-write.
- [ ] Compaction và device-backed test cho local storage v2.
- [ ] BLoC/widget/device integration coverage.
- [x] Local vault thuộc installation và độc lập Supabase user.

Exit criteria: TOTP, persistence và lock có regression/integration coverage trên platform chính.

## Giai đoạn 2 — Thiết kế lại sync

- [x] UI và sync dùng chung account-state owner.
- [x] Partial merge failure dừng upload.
- [x] Merge giữ stable ID và chỉ báo success sau local persistence.
- [x] ADR cho encrypted snapshot, optimistic revision và atomic publication.
- [ ] Thay xóa-rồi-chèn bằng protocol atomic/idempotent.
- [ ] Tombstone hoặc revisioned snapshot.
- [ ] Interrupted write/retry/two-device tests.

Exit criteria: network hoặc concurrency failure không làm mất snapshot hợp lệ gần nhất.

## Giai đoạn 3 — E2EE

- [x] ADR key hierarchy/recovery.
- [x] AES-256-GCM snapshot primitive và recovery-key wrapping có version.
- [ ] Onboarding UI, export/import recovery key và multi-device recovery E2E.
- [ ] Migration row plaintext.
- [ ] Chứng minh backend chỉ thấy ciphertext.

Exit criteria: backend-blind secret storage được test và review.

## Giai đoạn 4 — Auth và product flow

- [x] Local vault offline-first; Supabase login chỉ cho cloud feature.
- [x] Chọn Web recovery và version-control template token-hash.
- [ ] Deploy recovery template/allow-list và test email E2E.
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
- [x] Recovery Web có runtime config, dependency pin và container/header hardening.
- [ ] Recovery Web end-to-end, email template và production hosting review.
- [ ] Release provenance, rollback và incident process.

Exit criteria: gate trong `DEPLOYMENT.md` pass riêng cho từng platform được quảng bá.

## Quy tắc chọn việc

Ưu tiên blocker làm lộ credential hoặc mất dữ liệu trước convenience feature, trừ khi owner chấp nhận rủi ro rõ ràng. Mỗi hạng mục lớn dùng `docs/tasks/TEMPLATE.md` và ghi bằng chứng xác minh.
