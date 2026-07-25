# Roadmap

Roadmap ưu tiên theo giá trị của một ứng dụng authenticator và mức rủi ro dữ liệu.
Checkbox chỉ được đánh dấu khi có source/runtime evidence. Chi tiết lịch sử nằm
trong Git, không lặp lại ở tài liệu active.

## Product core đã có

- [x] TOTP local không cần tài khoản, network hoặc Supabase configuration.
- [x] Parse/validate `otpauth://totp`, Base32, SHA1/SHA256/SHA512, 6–8 chữ số và
  period tùy chỉnh.
- [x] Thêm bằng camera, ảnh QR hoặc thủ công theo capability platform.
- [x] Tìm kiếm, sửa, xóa, sao chép mã và countdown theo period.
- [x] Local vault versioned copy-on-write, rollback, compaction và logout giữ data.
- [x] App lock fail closed, relock theo lifecycle và Privacy Shield opaque.
- [x] UI tiếng Việt, theme system/light/dark, shell navigation giữ state.
- [x] Backup cloud E2EE tùy chọn trên native, recovery key và conflict resolution.
- [x] GitHub Preview cho signed Android APK, Windows installer và Linux package.

## P0 — Portability an toàn

Đây là khoảng trống sản phẩm lớn nhất so với Google Authenticator.

- [ ] Import Google Authenticator migration QR, gồm multi-part batch, duplicate
  detection và preview trước commit.
- [ ] Export nhiều account theo format có version; yêu cầu local reauthentication,
  cảnh báo secret exposure và timeout.
- [ ] Import/export chuẩn `otpauth` phổ biến mà không log, đưa secret vào semantics
  hoặc ghi đè vault khi một record lỗi.
- [ ] Backup file encrypted có password/KDF, schema version, integrity check và
  atomic import rollback.
- [ ] Regression interoperability với Google Authenticator fixtures
  `TEST_ONLY`, không dùng credential thật.

Exit criteria: round-trip giữ đủ issuer/name/algorithm/digits/period; cancel hoặc
payload lỗi không mutate vault; export chỉ mở sau reauthentication.

## P0 — Bảo toàn dữ liệu và security

- [ ] Independent application/cryptography review cho E2EE/device-wrap.
- [ ] User-facing cryptographic device exclusion. Session revoke hiện không phải
  remote wipe và generic rotation vẫn giữ active device có proof hợp lệ.
- [ ] Physical two-device conflict/recovery test trên Android/iOS đại diện.
- [ ] Threat model và native runtime evidence cho app-switcher snapshot, active
  screenshot/recording và clipboard history.
- [ ] Formal retention/delete-all contract cho local account, cloud snapshot và
  Supabase identity.

## P1 — UX authenticator

- [ ] Account grouping, pin/favorite và reorder không làm đổi TOTP identity.
- [ ] Batch select cho delete/export với destructive confirmation an toàn.
- [ ] QR scan quality: torch, zoom, duplicate feedback và permission recovery trên
  thiết bị thật.
- [ ] TalkBack/VoiceOver, reduced-motion và full keyboard/focus audit trên platform
  đại diện.
- [ ] Performance benchmark cho 100/500 account; không regenerate mã ngoài time
  window cần thiết.
- [ ] Optional issuer icon chỉ khi provenance/license rõ ràng; không network-track
  dịch vụ người dùng.

Không ưu tiên push approval, password manager hoặc proprietary MFA protocol trong
giai đoạn này; chúng làm đổi product/security boundary vượt khỏi TOTP authenticator.

## P1 — Phát hành

- [ ] macOS Developer ID, hardened runtime, notarization, staple và runtime smoke.
- [ ] iOS distribution certificate/profile và TestFlight/App Store khi owner sẵn
  sàng.
- [ ] Windows code signing và Windows Hello physical-device evidence.
- [ ] Linux KDE/physical desktop và signed package channel.
- [ ] Host privacy policy, support contact và security contact ở URL công khai.
- [ ] SMTP mailbox delivery cùng expired/reused recovery-link E2E.

## P1 — Reliability/operations

- [ ] Off-host backup không phụ thuộc máy Mac cá nhân.
- [ ] External alerting cho Auth latency, disk, container health, backup age và
  restore drill.
- [ ] Staging Supabase upgrade rehearsal theo upstream stable pin.
- [ ] Incident-response exercise và non-Web release rollback drill.
- [ ] Long-duration workload budget; current low-concurrency check chưa phải SLA.

## P2 — Cloud và Web

- [ ] Tách rõ advanced device/session administration khỏi Settings phổ thông; chỉ
  đưa lại UI khi semantics revoke/exclusion đủ chính xác.
- [ ] Đánh giá trusted-device transfer sau portability P0.
- [ ] Chỉ xem xét Web E2EE sau browser key-storage threat model; mặc định vẫn tắt.
- [ ] Tách self-hosted infrastructure harness/runbook sang repository vận hành khi
  owner đã có nơi chứa secret rotation, monitoring và deployment lifecycle riêng.

## Quy tắc chọn việc

Credential exposure, mất dữ liệu, auth bypass và backup không thể khôi phục luôn
ưu tiên trước convenience. Storage/schema/crypto change phải có migration,
rollback và regression test. Tính năng dự kiến không được mô tả như đã triển khai.
