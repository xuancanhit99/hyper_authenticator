# Trạng thái dự án

Baseline được cập nhật ngày **29 tháng 7 năm 2026** trên macOS 26.5.1. File này
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

- Parse bounded `otpauth://totp`; validate Base32, SHA1/SHA256/SHA512, digits
  6–8, period dương và từ chối security parameter bị lặp. Persisted field
  round-trip không tự về default.
- Thêm account bằng camera, ảnh QR hoặc thủ công theo platform capability.
- Import standard `otpauth` luôn preview issuer/account/parameter không chứa
  secret; cancel không mutate, confirm dùng validate-all, exact dedupe và một
  atomic COW append commit.
- Import Google Authenticator migration QR version 1 và wire shape version 2 đã
  quan sát từ Google Authenticator 7.2, gồm multi-part out-of-order, preview,
  duplicate detection và một atomic append commit. HOTP/MD5/version hoặc metadata
  lạ fail closed.
- Export nhiều account thành Google migration QR version 1 sau fresh OS auth.
  Encoder fail closed với semantics Google không biểu diễn được, tự chia part;
  QR có cảnh báo, timeout 60 giây và bị xóa khi app rời foreground. Nếu OS auth
  trả success trước lifecycle `resumed`, page chỉ chờ tối đa 2 giây rồi fail
  closed, không tạo QR ở background.
- Cùng protected export page cho phép chọn standard `otpauth`: một QR cho mỗi
  account, tối đa 100 account, giữ algorithm/digits/period và validate toàn bộ
  trước khi tạo list. URI/secret chỉ nằm trong widget memory sau fresh OS auth.
- Tìm kiếm, sửa, xóa, sao chép TOTP và countdown theo period.
- Account actions dùng menu Material. Google transfer và standard `otpauth` chỉ
  xuất qua disclosure flow riêng, không tái dùng app-lock success.
- FlutterSecureStorage dùng versioned copy-on-write generation, commit marker,
  rollback generation và compaction giữ hai generation hợp lệ gần nhất.
- Settings có backup file portable `.hyauth` trên cả sáu target: Argon2id v19
  derive key từ password, AES-256-GCM xác thực ciphertext/header, envelope và
  plaintext schema version 1. Restore decrypt/validate toàn bộ, preview metadata,
  bắt gõ xác nhận phá hủy rồi mới replace local vault bằng một COW commit.
- Android lưu bằng Storage Access Framework `ACTION_CREATE_DOCUMENT`, chỉ báo
  thành công sau khi ghi xong document URI. iOS dùng share sheet với Files;
  Web/desktop giữ download/save dialog theo platform.
- File/password cancel, wrong password, tamper, future version, oversized input,
  lifecycle rời foreground hoặc preview timeout đều không mutate vault.
- Logout không xóa local vault. Windows giữ storage identity tương thích
  `1.0.0+9`; migration conflict fail closed.

### Bootstrap, navigation và state

- Không có toàn bộ cloud define là local-only hợp lệ; Supabase không được khởi
  tạo và auth deep link quay về local app.
- Cloud-enabled build yêu cầu đủ HTTPS Supabase URL, publishable/legacy `anon`
  key và recovery URL. Partial config, service-role/secret key hoặc
  `ALLOW_INSECURE_PLAINTEXT_SYNC=true` đều fail closed.
- Accounts và Settings dùng `StatefulShellRoute.indexedStack`; đổi tab giữ state,
  không chạy full-page transition, chọn lại tab hiện tại quay về branch root.
  Viewport compact dùng `NavigationBar`; desktop từ 900 px dùng
  `NavigationRail`. Route phân cấp giữ transition native theo platform.
- Feature state dùng BLoC/Cubit; theme có một `ThemeCubit`. Root không tạo trùng
  `SettingsBloc`.
- Remember Me đã bỏ; Supabase sở hữu session persistence, app không lưu lại
  email/password preference.

### App lock, privacy và accessibility

- App lock dùng OS local authentication ở platform hỗ trợ; plugin error không
  bypass lock. Lifecycle rời foreground thông thường kích hoạt relock theo policy.
  System picker/share do app chủ động mở giữ route trong lúc chờ kết quả; Privacy
  Shield vẫn che toàn bộ nội dung và interaction.
- Root Privacy Shield render surface Material 3 opaque ở
  `inactive/hidden/paused/detached`, bỏ focus, chặn interaction/ticker và loại
  nội dung bên dưới khỏi semantics.
- UI chính dùng tiếng Việt; thuật ngữ TOTP, Base32, cloud, recovery key giữ khi
  cần chính xác.
- Form Auth, tài khoản, Settings và Backup có max-width responsive; empty state
  phân biệt vault trống với search trống. Secret nhập tay được che mặc định và
  tắt personalized IME learning. Xóa account chỉ báo thành công sau khi persist.
- Lock screen dùng responsive Material 3 layout, hỗ trợ scroll ở viewport hẹp và
  text scale lớn; lifecycle resume giữ shell/tab có thể tương tác.
- Settings tách device security, backup cloud, account/session và backup file
  thành card độc lập. Card tương tác clip pressed overlay theo bo góc 16 px; button
  Filled/Elevated/Outlined giữ touch target 48 px, padding ngang và semantic color
  theo light/dark theme. Advanced disclosure không dùng default border theo state;
  action/divider thẳng hàng content edge 56/24 px của ListTile.
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
| `flutter analyze` | Pass, 0 diagnostic ngày 30-07-2026 |
| `scripts/agent/check.sh full` | Pass ngày 30-07-2026; tổng hợp bốn boundary dưới đây |
| `scripts/agent/check.sh app` | Pass ngày 30-07-2026: docs/generated/format/analyze/platform và 269 Flutter test |
| `scripts/agent/check.sh backend` | Pass ngày 30-07-2026: encrypted/device-wrap và plaintext-retirement PostgreSQL contract |
| `scripts/agent/check.sh release` | Pass ngày 30-07-2026: GitHub Preview asset/public contract và Web rollback harness |
| `scripts/agent/check.sh infra` | Pass ngày 30-07-2026: NPM secret/backup/deploy/route/rollback, Auth load pacing và restore drill contract |
| Local release smoke | Android signed APK + checksum/pinned signer, Web release + Chrome runtime, iOS development-signed device release build và macOS unsigned compile pass ngày 30-07-2026 |
| Android 17/API 37.1 AVD | Local vault Add/Edit/Delete/TOTP, standard + Google migration import/export, camera-frame QR, lifecycle, Auth UI, E2EE và encrypted backup pass; physical camera/biometric còn thiếu |
| Encrypted backup Android/iOS | Android 17/API 37.1 và iOS 27.0 pass cancel/save local, tamper, wrong password, preview cancel, clean-vault atomic restore và cleanup ngày 30-07-2026 |
| iOS 27.0 Simulator + iPhone 16 Pro | Simulator pass local vault/import-export, encrypted backup, lifecycle/navigation và Face ID app-lock; local Ad Hoc app đã ký/cài trên thiết bị thật, launch bị chặn vì máy khóa nên runtime/camera còn thiếu |
| macOS | Unsigned compile pass; Apple Development identity có nhưng thiếu Xcode account/Mac provisioning profile, nên signed Keychain runtime còn thiếu |
| Windows hosted | Historical vault upgrade, local-vault runtime, release bundle và unsigned NSIS pass |
| Linux hosted/container | Historical upgrade, private keyring, `.deb`, distro matrix và authenticated E2EE debug runtime pass |
| Flutter Web production | HTTPS/Nginx/runtime/rollback smoke đã pass; E2EE backup tắt |
| GitHub Preview | `v1.1.0-preview.5`: signed Android APK, unsigned Windows NSIS và Linux `.deb`; tag CI `30391446163` và public verifier `30392505826` pass exact seven-asset/checksum/signature contract |

Encrypted backup runtime rehearsal phát hiện và đã sửa hai gap Android: share
sheet không bảo đảm local save nên được thay bằng native document picker; app-lock
không còn dispose route đang chờ trusted system UI. Không đổi local-vault v2,
file schema v1, cloud encrypted envelope, Supabase schema/RPC hoặc production data.
Full feature acceptance ngày 30-07-2026 còn pass Auth UI logout-preserves-vault,
native two-session E2EE revision 1→4, 36 encrypted remote checks, 25 device registry
checks, 8 recovery-token checks và plaintext table-absent; isolated user được
admin probe 404 sau cleanup.

## Capability matrix

| Platform | TOTP local | QR camera | QR từ ảnh | App lock | Protected QR export | Backup file mã hóa | Backup cloud E2EE |
|---|---:|---:|---:|---:|---:|---:|---:|
| Android | Có | Có | Có | Có | Có | Có | Có |
| iOS | Có | Có | Có | Có | Có | Có | Có |
| macOS | Có | Có | Có | Có | Có | Có | Có |
| Windows | Có | Không | Không | Có | Có | Có | Có |
| Linux | Có | Không | Không | Không | Không | Có | Có |
| Web | Có | Có | Không | Không | Không | Có | Không |

Đây là source capability, không thay thế physical-device/store evidence.

## Support và phân phối

| Platform | Kênh hiện tại | Gate còn lại trước stable |
|---|---|---|
| Android | Signed APK qua GitHub Preview | Camera, biometric và upgrade trên thiết bị thật; Play Store để sau |
| iOS | Local Ad Hoc trên thiết bị đăng ký | Còn physical runtime/camera/secure storage/VoiceOver, archive và TestFlight/App Store |
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

1. **Portability:** Google migration QR đã pass app-to-app hai chiều với Google
   Authenticator 7.2 trên Android AVD; standard `otpauth` đã có bounded
   round-trip/preview/protected export regression. Backup file v1 đã pass
   backup → clean install → restore trên Android AVD và iOS Simulator, nhưng chưa
   có evidence trên physical Android/iOS hoặc packaged desktop. Còn physical
   interoperability Android/iOS cho standard/current Google export.
2. **Device exclusion:** session revoke chưa phải cryptographic exclusion hoặc
   remote wipe; cần UX và independent security review.
3. **Thiết bị thật:** Android camera AVD và iOS Face ID Simulator đã pass; camera,
   biometric, secure storage, TalkBack/VoiceOver,
   two-device conflict/recovery chưa có đủ representative evidence.
4. **Signing:** iOS development build và local Ad Hoc install đã pass; launch
   smoke chưa chạy vì thiết bị khóa, archive/TestFlight còn thiếu. macOS thiếu
   Xcode account/profile và Developer ID; Windows chưa có code-signing certificate.
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
10. **Android toolchain:** `mobile_scanner 7.4.0` là bản mới nhất resolvable và
    camera smoke pass, nhưng Flutter còn cảnh báo Kotlin Gradle Plugin; cần migrate
    Built-in Kotlin trước khi warning trở thành build failure.

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
