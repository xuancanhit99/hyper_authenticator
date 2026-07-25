# Trạng thái dự án

Baseline được cập nhật ngày **23 tháng 7 năm 2026** trên macOS 26.5.1. File này
chỉ giữ trạng thái hiện tại; log rollout/CI/backup theo từng lần chạy nằm trong
Git history và `docs/operations`.

## Kết luận

Hyper Authenticator là ứng dụng TOTP Flutter đa nền tảng, local-first:

- TOTP local không cần tài khoản, network hoặc Supabase configuration.
- Android, iOS, macOS, Windows, Linux và Web có platform runner.
- Supabase Auth và backup cloud E2EE là capability tùy chọn trên native.
- Web không bật E2EE backup vì browser storage không có trust boundary tương
  đương Keychain/Keystore.
- GitHub Releases là kênh binary hiện tại; stable/store release còn gate signing,
  legal/support metadata và physical-device evidence.

Source và production backend đã có baseline bảo mật cao hơn một app TOTP tối
thiểu: local vault copy-on-write, Privacy Shield, encrypted snapshot, RLS/RPC,
device-bound HPKE wrap, backup/restore và release harness. Phần phức tạp này được
giữ ở data/security boundary; primary UI không yêu cầu người dùng hiểu revision,
session registry hoặc vault-key generation.

## Runtime đã triển khai

### TOTP và local vault

- Parse `otpauth://totp`; validate Base32, SHA1/SHA256/SHA512, digits 6–8 và
  period dương; persisted field round-trip không tự về default.
- Thêm account bằng camera, ảnh QR hoặc thủ công theo platform capability.
- Tìm kiếm, sửa, xóa, sao chép TOTP và countdown theo period.
- Account actions dùng menu Material. Primary UI không còn xuất raw `otpauth` QR
  chưa được tái xác thực.
- FlutterSecureStorage dùng versioned copy-on-write generation, commit marker,
  rollback generation và compaction giữ hai generation hợp lệ gần nhất.
- Logout không xóa local vault. Windows giữ storage identity tương thích
  `1.0.0+9`; migration conflict fail closed.

### Bootstrap, navigation và state

- Không có toàn bộ cloud define là local-only hợp lệ; Supabase không được khởi
  tạo và auth deep link quay về local app.
- Cloud-enabled build yêu cầu đủ HTTPS Supabase URL, publishable/legacy `anon`
  key và recovery URL. Partial config, service-role/secret key hoặc
  `ALLOW_INSECURE_PLAINTEXT_SYNC=true` đều fail closed.
- Accounts và Settings dùng `StatefulShellRoute.indexedStack`; đổi tab giữ state,
  không chạy full-page transition.
- Feature state dùng BLoC/Cubit; theme có một `ThemeCubit`. Root không tạo trùng
  `SettingsBloc`.
- Remember Me đã bỏ; Supabase sở hữu session persistence, app không lưu lại
  email/password preference.

### App lock, privacy và accessibility

- App lock dùng OS local authentication ở platform hỗ trợ; plugin error không
  bypass lock. Lifecycle rời foreground kích hoạt relock theo policy.
- Root Privacy Shield render surface Material 3 opaque ở
  `inactive/hidden/paused/detached`, bỏ focus, chặn interaction/ticker và loại
  nội dung bên dưới khỏi semantics.
- UI chính dùng tiếng Việt; thuật ngữ TOTP, Base32, cloud, recovery key giữ khi
  cần chính xác.
- Widget regression có light/dark, text scale 200%, tap target, text contrast,
  keyboard focus và credential redaction trên các luồng cốt lõi.

Privacy Shield không phải active screenshot/recording prevention. TalkBack,
VoiceOver và native app-switcher snapshot vẫn cần thiết bị thật.

### Backup cloud E2EE

- UI gọi tính năng là **backup cloud mã hóa đầu cuối**, chỉ hiện khi cloud config
  đầy đủ và platform hỗ trợ.
- AES-256-GCM versioned snapshot, recovery key do người dùng giữ, optimistic
  revision, conflict review và atomic publish đã triển khai.
- Recovery decrypt/validate trước khi atomic replace local vault.
- Recovery-key rotation nằm trong **Bảo mật nâng cao**.
- Session registry, targeted revoke và generic vault-key rotation code/backend
  contract vẫn tồn tại nhưng không còn trong primary Settings.
- Plaintext sync client path đã xóa. Terminal migration chỉ drop legacy
  `synced_accounts` dưới `ACCESS EXCLUSIVE` lock khi bảng rỗng; có row thì rollback
  nguyên transaction.
- Device-bound update dùng HPKE wrap, active-session check, all-active membership
  proof và exact revision/generation row lock.

Targeted/bulk session revoke không remote-wipe local TOTP hoặc DEK đã lưu. Generic
key rotation hiện vẫn cấp wrap cho mọi active device có proof hợp lệ; chưa có
user-facing cryptographic device exclusion.

## Bằng chứng gần nhất

| Gate | Kết quả |
|---|---|
| `flutter analyze` | Pass, 0 diagnostic ngày 23-07-2026 trên nhánh đơn giản hóa |
| `scripts/agent/check.sh full` | Pass trạng thái cuối ngày 23-07-2026; tổng hợp bốn boundary dưới đây |
| `scripts/agent/check.sh app` | Pass ngày 23-07-2026: docs/generated/format/analyze/platform và 189 Flutter test |
| `scripts/agent/check.sh backend` | Pass ngày 23-07-2026: encrypted/device-wrap và plaintext-retirement PostgreSQL contract |
| `scripts/agent/check.sh release` | Pass ngày 23-07-2026: GitHub Preview asset/public contract và Web rollback harness |
| `scripts/agent/check.sh infra` | Pass ngày 23-07-2026: NPM secret/backup/deploy/route/rollback, Auth load pacing và restore drill contract |
| Local-only release smoke | Web release build + Chrome engine/semantics/local-vault shell pass; Android debug APK build pass |
| Android Pixel AVD | Signed build, clean install, vault-retaining upgrade và E2EE flows đã pass; physical camera/biometric còn thiếu |
| iOS Simulator | Local vault và authenticated E2EE flows đã pass; device/signing còn thiếu |
| macOS | Unsigned compile pass; signing/Keychain release runtime còn thiếu |
| Windows hosted | Historical vault upgrade, local-vault runtime, release bundle và unsigned NSIS pass |
| Linux hosted/container | Historical upgrade, private keyring, `.deb`, distro matrix và authenticated E2EE debug runtime pass |
| Flutter Web production | HTTPS/Nginx/runtime/rollback smoke đã pass; E2EE backup tắt |
| GitHub Preview | `v1.1.0-preview.4`: signed Android APK, unsigned Windows NSIS và Linux `.deb`, checksum/public verification pass |

Current change set chỉ đổi bootstrap/UI/state/docs; không đổi local-vault format,
encrypted envelope, Supabase schema/RPC hoặc production data.

## Capability matrix

| Platform | TOTP local | QR camera | QR từ ảnh | App lock | Backup cloud E2EE |
|---|---:|---:|---:|---:|---:|
| Android | Có | Có | Có | Có | Có |
| iOS | Có | Có | Có | Có | Có |
| macOS | Có | Có | Có | Có | Có |
| Windows | Có | Không | Không | Có | Có |
| Linux | Có | Không | Không | Không | Có |
| Web | Có | Có | Không | Không | Không |

Đây là source capability, không thay thế physical-device/store evidence.

## Support và phân phối

| Platform | Kênh hiện tại | Gate còn lại trước stable |
|---|---|---|
| Android | Signed APK qua GitHub Preview | Camera, biometric và upgrade trên thiết bị thật; Play Store để sau |
| iOS | Chưa phân phối | Apple credential, physical device, TestFlight/App Store |
| macOS | Chưa phân phối | Developer ID, hardened runtime, notarization, staple, runtime smoke |
| Windows | Unsigned NSIS Preview | Code signing và Windows Hello/physical-device |
| Linux | Unsigned `.deb` Preview | KDE/physical desktop, signed repository/channel |
| Web | Production HTTPS | Browser camera smoke; Web E2EE không nằm trong support tier |

## Production backend/operations

- Self-hosted Supabase pin có 11 core container và PostgreSQL 17; public HTTPS,
  Studio Basic Auth, RLS/RPC/device-wrap/active-session contract đã deploy.
- Final data audit sau terminal migration: legacy plaintext table absent; test
  user/snapshot/device rows đã cleanup.
- Backup có checksum, full restore rehearsal, encrypted off-host copy, health và
  scheduled restore timer.
- Nginx Proxy Manager đã dùng file secrets và pinned images; Hyper
  Authenticator/Supabase critical route matrix pass.

Chi tiết command, rollback và evidence retention:

- [Supabase production operations](operations/SUPABASE_PRODUCTION_OPERATIONS.md)
- [Supabase E2EE rollout](operations/SUPABASE_E2EE_ROLLOUT.md)
- [Supabase recovery rollout](operations/SUPABASE_RECOVERY_ROLLOUT.md)
- [Legacy backup/restore note](operations/SUPABASE_LEGACY_BACKUP.md)
- [Web deployment](../web-deployment/README.md)

## Khoảng trống ưu tiên

1. **Portability:** chưa import Google Authenticator migration QR, multi-account
   export hoặc encrypted backup file. Đây là P0 product tiếp theo.
2. **Device exclusion:** session revoke chưa phải cryptographic exclusion hoặc
   remote wipe; cần UX và independent security review.
3. **Thiết bị thật:** camera, biometric, secure storage, TalkBack/VoiceOver,
   two-device conflict/recovery chưa có đủ representative evidence.
4. **Signing:** Apple và Windows credential chưa có; macOS/iOS/Windows stable bị
   chặn tương ứng.
5. **Recovery email:** SMTP mailbox delivery và expired/reused link E2E chưa xác
   minh.
6. **Legal/support:** privacy policy/support/security contact cần URL công khai
   trước stable/store.
7. **Operations SLA:** alert ngoài host chưa có; off-host backup còn phụ thuộc máy
   Mac; load check hiện tại chưa phải production SLA.
8. **Web trust boundary:** browser local storage yếu hơn native; không bật E2EE
   backup cho tới khi có threat model riêng.
9. **Infrastructure ownership:** Supabase/NPM operations harness còn cùng
   repository. Gate đã tách `infra`; physical move sang repository vận hành được
   hoãn tới khi owner có lifecycle/deployment repository riêng.

## Gate canonical

    scripts/agent/check.sh docs
    scripts/agent/check.sh quick
    scripts/agent/check.sh app
    scripts/agent/check.sh backend
    scripts/agent/check.sh release
    scripts/agent/check.sh infra
    scripts/agent/check.sh full

`full` tổng hợp `app + backend + release + infra`. Emulator/simulator, browser
runtime, protected production operator test và signing gate vẫn chạy riêng theo
platform/runbook.

Chỉ cập nhật trạng thái khi có source hoặc test/runtime evidence tái hiện được.
