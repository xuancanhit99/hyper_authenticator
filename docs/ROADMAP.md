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
- [x] Primary UI tiếng Việt và Web document language `vi`; giữ thuật ngữ technical
  khi cần độ chính xác.

## Ưu tiên P0 — Duy trì GitHub Releases làm kênh phân phối chính

- [x] Chấp nhận contract GitHub Preview unsigned cho Windows x64/Linux amd64.
- [x] Harness bắt buộc tag/version/tag-CI/checksum/asset allowlist và pre-release flag.
- [x] Publish `v1.1.0-preview.1` và xác minh lại public download/checksum.
- [x] Công bố private security reporting trên GitHub.
- [x] Chốt app store và SMTP là milestone hoãn, không chặn GitHub Preview.
- [x] Phát hành `v1.1.0-preview.4` từ tested tag và xác minh public download.
- [x] Chốt Android app-signing key dùng lâu dài và pin public certificate SHA-256.
- [x] Thêm signed APK vào GitHub Releases sau signed build/runtime/upgrade gate;
  không cần chờ Play Store.
- [ ] Thêm macOS package sau Developer ID/notarization/runtime gate; không phát
  hành unsigned compile artifact.

Exit criteria: GitHub pre-release public có Android/Windows/Linux artifact đúng
contract, tag CI xanh, checksum tải lại khớp và release note nêu signing/SMTP/platform risk.

## Ưu tiên P1 — Reliability và operations

- [ ] Đưa encrypted off-host backup lên backup host/object storage độc lập Mac cá nhân.
- [ ] Alerting + dashboard/SLO cho Auth latency, container health, disk, backup age.
- [ ] Staging upgrade rehearsal định kỳ theo official Supabase pin.
- [x] Scheduled restore drill với retry, shared backup lock, atomic evidence và
  health freshness gate.
- [x] Low-concurrency public Auth load có budget và acceptance threshold.
- [ ] Long-duration soak và production-scale workload có budget riêng.
- [x] Flutter Web live rollback→forward drill với auto-restore và exact artifact gate.
- [ ] Incident response exercise và non-Web release rollback drill; periodic
  database restore và Web rollback đã tự động hóa riêng.

## Ưu tiên P1 — Product/security

- [x] Device registry bind server-side và targeted auth-session revocation.
- [x] Device-specific HPKE key wrap, exact surviving wrap-set rotation và
  cryptographic read revocation đã deploy production; physical two-device và
  independent review vẫn là gate riêng.
- [ ] Trusted-device hoặc QR recovery transfer.
- [ ] Export/delete account/data UX và retention policy.
- [ ] Localization đa ngôn ngữ.
- [x] Automated accessibility baseline cho Auth/accounts/add-account và Settings
  recovery/conflict/session dialog; TOTP secret key/raw recovery key không vào
  semantics tree.
- [x] Automated WCAG text contrast light/dark và core keyboard traversal cho
  Auth/accounts/add-account/sensitive Settings dialog.
- [x] Lifecycle privacy shield che router ở mọi trạng thái khác `resumed`, có
  regression cho focus, interaction và semantics.
- [ ] TalkBack/VoiceOver runtime, full Settings/main-navigation keyboard audit,
  reduced-motion, native app-switcher snapshot và active screenshot/recording
  review trên platform đại diện.
- [ ] Independent cryptographic/application security review.

## Ưu tiên P2 — Platform expansion

- [x] Windows NSIS unsigned candidate + hosted install/launch/metadata-upgrade/
  uninstall data-retention smoke.
- [x] Windows historical-release upgrade từ source `1.0.0+9` sang current COW v2.
- [ ] Windows code signing và physical-device/Windows Hello.
- [x] Linux configured release + private libsecret/keyring headless smoke.
- [x] Linux `.deb` dependency/checksum + clean-container package transition smoke.
- [x] Linux authenticated E2EE debug runtime với isolated production test user.
- [x] Linux hosted amd64 historical upgrade + Ubuntu/Debian X11/Wayland matrix.
- [ ] Linux KDE login-unlock/physical desktop, signed package runtime và release channel.
- [ ] Quyết định Web encrypted sync sau browser threat model; mặc định vẫn tắt.
- [ ] Đánh giá alternative scanner nếu upstream Built-in Kotlin migration chậm.

## Ưu tiên P2 — Signed GitHub Release và app store (đang hoãn)

- [x] Owner tạo Android app-signing keystore ngoài repository; source pin public
  fingerprint và có local/CI signing harness fail closed.
- [x] Build signed APK, xác minh signer và pass clean-install/vault-retaining
  upgrade trên Android AVD.
- [x] Upload đủ bốn GitHub encrypted signing secrets sau khi owner xác nhận backup.
- [x] Chạy tag CI và public signed APK; public verifier xác minh đúng signer. Nếu mở
  Play Store, reuse app signing key để giữ cross-channel upgrade rồi tách upload
  key cho AAB/internal track.
- [ ] Owner cung cấp Apple certificate/profile; macOS GitHub package cần
  notarization, còn iOS TestFlight/App Store là milestone riêng.
- [ ] Windows code-signing certificate và signed installer verification.
- [ ] Host privacy policy + support contact ở URL công khai.
- [ ] Mailbox test SMTP delivery và expired recovery link.
- [ ] Device smoke: Keychain/Keystore, biometric, camera, recovery, two-device conflict.
- [ ] Cấu hình external alert channel cho systemd health/backup failure.

## Quy tắc chọn việc

Credential exposure, data loss, auth bypass và unrecoverable backup luôn ưu tiên
trước convenience. Mọi storage/schema/crypto change phải có migration, rollback và test.
