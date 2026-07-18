# Roadmap

Roadmap ưu tiên theo rủi ro. Checkbox chỉ được đánh dấu khi có source/runtime evidence.

## Baseline đã hoàn thành

- [x] Flutter/Dart/dependency/native toolchain hiện đại hóa.
- [x] Compile-time public config; `.env` không bundle.
- [x] CI đa nền tảng, docs/generated/format/analyze/test gate.
- [x] Apache-2.0 cho source.
- [x] Loại font/logo bên thứ ba không rõ provenance khỏi artifact.
- [x] Local vault versioned copy-on-write, rollback và compaction.
- [x] TOTP field round-trip, validation, countdown theo period.
- [x] Logout giữ data; app lock fail closed/relock.
- [x] Supabase self-hosted pin, HTTPS/proxy/Studio/RLS hardening.
- [x] Recovery Web token-hash contract.
- [x] AES-256-GCM encrypted snapshot, recovery key onboarding/import.
- [x] Atomic optimistic revision RPC và explicit conflict UX.
- [x] Client plaintext runtime bridge bị loại khỏi DI/release.
- [x] Daily verified backup, restore rehearsal, encrypted off-host copy và health timer.

## Ưu tiên P0 — Phát hành platform đầu tiên

- [ ] Owner cung cấp Android upload keystore; build AAB signed và internal track test.
- [ ] Owner cung cấp Apple certificate/profile; iOS TestFlight và macOS notarization.
- [ ] Host privacy policy + support/security contact ở URL công khai.
- [ ] Mailbox test SMTP delivery và expired recovery link.
- [ ] Device smoke: Keychain/Keystore, biometric, camera, recovery, two-device conflict.
- [ ] Cấu hình external alert channel cho systemd health/backup failure.

Exit criteria: ít nhất một platform có signed artifact, store/device gate, public
policy và backend rollback evidence.

## Ưu tiên P1 — Reliability và operations

- [ ] Đưa encrypted off-host backup lên backup host/object storage độc lập Mac cá nhân.
- [ ] Alerting + dashboard/SLO cho Auth latency, container health, disk, backup age.
- [ ] Staging upgrade rehearsal định kỳ theo official Supabase pin.
- [ ] Soak/load test có budget và acceptance threshold.
- [ ] Incident response, restore drill lịch định kỳ và release rollback drill.

## Ưu tiên P1 — Product/security

- [ ] Device registry/revocation và key rotation protocol.
- [ ] Trusted-device hoặc QR recovery transfer.
- [ ] Export/delete account/data UX và retention policy.
- [ ] Localization đầy đủ, accessibility audit và screenshot/privacy review.
- [ ] Independent cryptographic/application security review.

## Ưu tiên P2 — Platform expansion

- [x] Windows NSIS unsigned candidate + hosted install/launch/metadata-upgrade/
  uninstall data-retention smoke.
- [x] Windows historical-release upgrade từ source `1.0.0+9` sang current COW v2.
- [ ] Windows code signing và physical-device/Windows Hello.
- [x] Linux configured release + private libsecret/keyring headless smoke.
- [x] Linux `.deb` dependency/checksum + clean-container package transition smoke.
- [x] Linux authenticated E2EE debug runtime với isolated production test user.
- [ ] Linux hosted historical upgrade, amd64/KDE login-unlock/physical desktop,
  signed package runtime và release channel; local arm64 X11/Wayland matrix đã pass.
- [ ] Quyết định Web encrypted sync sau browser threat model; mặc định vẫn tắt.
- [ ] Đánh giá alternative scanner nếu upstream Built-in Kotlin migration chậm.

## Quy tắc chọn việc

Credential exposure, data loss, auth bypass và unrecoverable backup luôn ưu tiên
trước convenience. Mọi storage/schema/crypto change phải có migration, rollback và test.
