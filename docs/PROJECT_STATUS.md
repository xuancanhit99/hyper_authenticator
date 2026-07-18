# Trạng thái dự án

Baseline được xác minh ngày **19 tháng 7 năm 2026** trên macOS 26.5.1.

## Kết luận hiện tại

Hyper Authenticator là ứng dụng Flutter TOTP local-first cho Android, iOS,
macOS, Windows, Linux và Web. Native client đã có encrypted cloud sync dùng
AES-256-GCM, recovery key do người dùng giữ, optimistic revision và atomic
publication qua Supabase RPC. Web vẫn chủ động tắt cloud sync vì browser storage
không có trust boundary tương đương platform secure storage.

Source, local data path, E2EE client/server contract, backup và backend health
harness đã đạt baseline kỹ thuật. Kênh binary đầu tiên được chuyển sang GitHub
Preview: Windows/Linux unsigned chỉ được public dưới dạng pre-release có checksum,
tag CI provenance và cảnh báo rõ ràng. Store/signed stable vẫn cần credential thuộc
owner; không mô tả preview là stable production release.

## Toolchain và dependency

- Flutter 3.44.6 stable; Dart 3.12.2; constraint `^3.12.0`.
- Phiên bản ứng dụng `1.1.0+10`.
- Direct dependency đều ở bản mới nhất solver hiện tại chấp nhận.
- `build_runner` giữ ở 2.15.1: 2.15.2 yêu cầu `meta ^1.18.3`, trong khi
  `flutter_test` của Flutter 3.44.6 pin `meta 1.18.0`.
- `mobile_scanner` 7.3.0 vẫn phát cảnh báo upstream về Kotlin Gradle Plugin
  legacy; build hiện pass nhưng phải theo dõi trước Flutter breaking release kế.
- `local_auth_windows` 2.0.1 vẫn dùng coroutine experimental; MSVC 14.51 cần
  `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`. Platform gate giữ shim
  tạm thời cho tới khi upstream chuyển sang coroutine chuẩn.
- Apple runner dùng Swift Package Manager.

## Bằng chứng client

| Kiểm tra | Kết quả |
|---|---|
| `flutter doctor -v` | Pass, không có lỗi toolchain |
| `flutter analyze` | Pass, 0 diagnostic |
| `flutter test` | 106 test pass |
| Vietnamese UI contract | Primary auth/accounts/settings/add-edit surface đã dùng tiếng Việt; app khóa `Locale('vi')` cùng Material/Widgets/Cupertino localization delegate và widget test xác minh locale runtime, vẫn giữ thuật ngữ technical cần thiết |
| Platform configuration gate | Pass network/backup/signing/Keychain/ID |
| Release config validator | Pass với `.env` public hiện tại, không in key |
| Gitleaks full history | Pass sau exact allowlist RFC 6238 test vector |
| Android debug + Pixel AVD runtime | Pass build/install, Supabase auth, setup revision 1, recovery-key rotation revision 2, vault-key rotation revision 3, fresh-device recovery revision 3, bulk revoke session thật 2→1 và local-vault integration smoke có cleanup |
| Web release + hardened Nginx image | `1.1.0-ae1ab36` `linux/amd64` đang healthy trên production; local/public `main.dart.js` SHA-256 `1a0d63a6…f66ea6` khớp, 5 SPA route và TLS/HSTS/CSP/cache/Permissions-Policy pass; browser xác minh runtime `lang=vi`, Flutter render và console sạch |
| macOS debug compile unsigned | Pass; không phải runtime/signing evidence |
| iOS 26.5 simulator debug | Pass build/runtime với Supabase init và local-vault integration smoke có cleanup |
| Android release | Fail closed đúng thiết kế vì chưa có upload keystore |
| macOS release | Bị chặn vì chưa có development/distribution certificate |
| Linux release + Debian artifact | Pass configured `linux/x64`, historical `1.0.0+9` vault upgrade, private-keyring UI smoke và `.deb` `1.1.0+10` amd64; hosted amd64 pass clean transition/retention + X11/Wayland trên Ubuntu 22.04/24.04 và Debian 12/13 |
| Linux authenticated E2EE runtime | Pass trên Ubuntu 24.04 arm64 container tạm: client thật đăng nhập production Supabase, setup revision 1, sync revision 2, fresh-device recovery, recovery-key rotation revision 3, reject key cũ, vault-key rotation revision 4 và recovery cuối; operator xóa user/row và admin probe xác nhận 404 |
| Windows release + installer | Pass upgrade vault thật từ source `1.0.0+9`/plugin 3.1.2 sang current COW v2, configured x64 bundle, local-vault runtime và NSIS 3.12 unsigned candidate; install/launch/metadata-upgrade/uninstall giữ AppData pass, bundle + installer/checksum giữ 14 ngày |
| GitHub Desktop Preview | `v1.1.0-preview.1` public pre-release tại commit `6c3bd4b`; Windows x64 NSIS và Linux amd64 `.deb` cùng individual checksum + `SHA256SUMS.txt`; public unauthenticated re-download khớp SHA-256 |

Build không có `--dart-define-from-file` chỉ chứng minh compile. Runtime/release
verification phải inject `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` và
`PASSWORD_RECOVERY_URL` bằng compile-time define.

## Data và security path đã triển khai

- TOTP URI chỉ nhận `otpauth://totp`; validate Base32, SHA1/SHA256/SHA512,
  digits 6–8 và period dương.
- Local vault dùng versioned copy-on-write generation, commit marker, rollback
  generation và compaction giữ hai generation hợp lệ gần nhất.
- Windows khóa AppData identity tương thích `1.0.0+9`; startup migrator nhập
  atomic layout pre-release, giữ source và fail closed khi hai vault khác nhau.
- Logout không xóa vault; app lock fail closed và relock khi rời foreground.
- Encrypted sync chỉ được đăng ký trong runtime DI; plaintext compatibility
  bridge còn source cho migration/test nhưng không được inject và release luôn khóa.
- Setup sync chỉ persist DEK sau khi recovery key được xác nhận, encrypted
  snapshot publish thành công và read-after-write verification pass.
- Recovery decrypt/validate trước rồi atomic `replaceAccounts`; key sai hoặc
  payload lỗi không ghi đè vault local.
- Conflict buộc người dùng chọn cloud hoặc local. Giữ local tạo revision mới;
  dùng cloud chỉ replace khi revision vẫn đúng revision đã review.
- Recovery key có thể xoay bằng re-wrap cùng DEK và atomic publish revision mới;
  cancel/conflict giữ key cũ, ambiguous verification cảnh báo giữ key mới.
- Vault key có thể xoay bằng DEK + recovery key mới; current snapshot được
  re-encrypt atomically, DEK local chỉ thay sau verify và thiết bị giữ DEK cũ phải
  recovery lại.
- Remote request bind với Supabase user ID hiện tại để chặn race đổi session.
- Settings có bulk revoke mọi Supabase session khác; session hiện tại, local vault
  và DEK được giữ. Backend đối chiếu JWT `session_id` với `auth.sessions` trong cả
  RLS/RPC nên session đã revoke mất quyền encrypted vault ngay.
- Web Settings không mời đăng nhập để dùng cloud sync khi capability bị tắt.
- Primary UI đã dùng tiếng Việt nhất quán cho auth, navigation, accounts,
  add/edit, settings và user-facing failure; Web document khai báo `lang="vi"`.
  Tên sản phẩm cùng thuật ngữ technical như TOTP, secret key, Base32, cloud,
  revision và session được giữ khi cần độ chính xác.
- Scanner hiển thị trạng thái đang chờ quyền camera và lỗi permission/unsupported
  bằng tiếng Việt, có retry hoặc quay lại nhập thủ công thay vì nền đen không rõ trạng thái.
- Logo dịch vụ và font Averta không rõ license đã bị loại khỏi release; UI dùng
  avatar ký tự render bằng code. Data contract không thay đổi vì logo không persist.

## Supabase production đã xác minh

- Pin upstream self-hosted nằm trong `supabase/UPSTREAM_PIN`; stack có 11 core
  container healthy và PostgreSQL 17.6.1.136.
- Public API qua HTTPS; Studio qua HTTPS + Basic Auth; Kong/Supavisor không mở
  trực tiếp ra Internet.
- `encrypted_vault_snapshots` chỉ cấp SELECT cho authenticated owner có active
  session, bật và force RLS. Atomic RPC kiểm tra `auth.uid()` + `session_id` và trả
  `PT409` khi revision lệch hoặc `session_revoked` khi phiên đã bị thu hồi.
- Remote encrypted contract: 20/20 pass; recovery contract: 8/8 pass; Studio
  proxy/DNS/upstream/Basic Auth contract pass.
- Auth load budget dùng public key: 100/100 HTTP 200 ở concurrency 10; p95 578 ms,
  max 862 ms, dưới ngưỡng 1.000/2.000 ms. Negative path 1 ms bị từ chối đúng;
  gate không tạo user/payload. Health trước đó xác nhận 11 container healthy,
  RAM available khoảng 3,4 GiB và swap used khoảng 610 MiB.
- Health timer chạy mỗi 5 phút. Backup timer chạy hằng ngày, giữ 7 bản local.
- Backup gồm logical database, globals, quiesced Storage và sensitive config;
  có SHA-256, permission 0700/0600 và validation catalog/tar.
- Full restore rehearsal đã pass vào database tạm rồi tự động drop; xác minh
  `auth.users`, encrypted table và `FORCE RLS`.
- Restore drill timer đã enable: trigger hằng ngày, thực thi tối đa mỗi 7 ngày và
  retry ngày sau khi fail. Lượt production 19-07-2026 restore backup
  `supabase-20260718T100222Z` pass; evidence 0600/checksum khớp, health kiểm tra
  freshness 9 ngày và probe xác nhận không còn database tạm.
- Encrypted off-host copy qua `age` chạy bằng macOS LaunchAgent, giữ 14 bản;
  stream không tạo plaintext archive trên máy nhận.

## Ma trận capability

| Platform | TOTP local | QR camera | QR từ ảnh | App lock | E2EE sync |
|---|---:|---:|---:|---:|---:|
| Android | Có | Có | Có | Có | Có |
| iOS | Có | Có | Có | Có | Có |
| macOS | Có | Có | Có | Có | Có |
| Windows | Có | Không | Không | Có | Có |
| Linux | Có | Không | Không | Không | Có |
| Web | Có | Có | Không | Không | Không |

Capability là hành vi source hiện tại, không thay thế device test và store review.

## Khoảng trống đã biết

1. Signing/notarization/store credential chưa có trong môi trường; không tự tạo
   credential thay owner.
2. SMTP endpoint chấp nhận recovery flow và token contract pass, nhưng delivery
   tới mailbox thật cùng expired-token E2E chưa được chứng minh.
3. Monitoring mới ghi journal/exit status; chưa có alert channel ngoài host.
4. Off-host backup hiện phụ thuộc máy Mac/LaunchAgent đang hoạt động; cần đích
   object storage hoặc backup host độc lập nếu yêu cầu SLA cao.
5. Low-concurrency Auth budget đã enforce; chưa có long-duration soak hoặc
   production-scale workload test.
6. E2EE v1 đã có DEK rotation và bulk revoke mọi auth session khác với server-side
   enforcement. Chưa có device registry/revoke riêng từng thiết bị, device-specific
   key wrap, tombstone/history hoặc Web trust model. Backup cũ vẫn dùng key
   generation cũ.
7. Local-vault integration smoke đã pass Android emulator, iOS Simulator và
   GitHub-hosted Windows Server 2025; biometric/camera và secure-storage behavior
   trên thiết bị thật vẫn chưa được chứng minh. Mobile harness chủ động từ chối
   target thật/macOS vì nó reset toàn bộ local vault; Windows harness chỉ nhận
   hosted runner tạm.
8. Windows đã có unsigned NSIS candidate, hosted-runner package transition và
   upgrade thật từ source `1.0.0+9`; còn code signing và physical-device/Windows Hello.
   Linux đã có `.deb` candidate, hosted amd64 historical upgrade, clean-container
   package transition, X11/Wayland distro matrix và authenticated E2EE client runtime;
   hai package đã public trong `v1.1.0-preview.1` với nhãn unsigned. Trước stable còn KDE
   login/unlock/physical desktop, release signing và maintainer/support metadata.
   E2EE evidence hiện là
   debug arm64 container, không phải signed amd64 package runtime.
9. Privacy policy cần được host tại URL công khai và điền kênh support trước store submission.
10. Flutter Web đã pass TLS/reverse proxy và runtime smoke trên production domain;
   permission pending/error UX đã có regression test trên VM và Chrome test
   platform, nhưng camera/QR decode vẫn cần browser-device smoke thực tế.

## Automation

- `.github/workflows/ci.yml` chạy secret history, docs/generated-code/format/
  analyze/test và compile Android, iOS simulator, macOS unsigned, Web, Windows,
  Linux. Linux job build configured x64 trên Ubuntu 22.04, chạy private-keyring
  integration, tạo `.deb`, smoke package transition và bốn distro container rồi
  lưu checksum + artifact 14 ngày;
  Windows chạy historical `1.0.0+9` vault upgrade và local-vault integration,
  build configured bundle, tạo NSIS candidate,
  smoke install/launch/metadata-upgrade/uninstall giữ AppData và lưu hai artifact
  theo commit 14 ngày. Các gate này không thay signed runtime hoặc
  representative-device/distro matrix.
- GitHub Actions run `29652820428` tại `ae1ab36` pass 7/7; locale fix được xác
  minh cùng Linux hosted historical/package/distro, Windows historical/runtime/
  installer, Apple, Android, Web, quality và secret history gate.
- Tag CI run `29656402708` tại `v1.1.0-preview.1`/`6c3bd4b` pass 7/7. Release
  public có pre-release flag, không phải draft, đúng năm asset; Windows SHA-256
  `5bccb8f8…07a47`, Linux SHA-256 `2628ca05…46d33` đã được tải lại không auth và
  xác minh bằng manifest công khai.
- `.github/dependabot.yml` kiểm tra Pub và GitHub Actions hằng tuần.
- `release-preview.yml` cùng `github_preview_release.sh` fail closed theo
  tag/version/successful tag CI và chỉ publish Windows/Linux allowlist với checksum;
  workflow thủ công chỉ hoạt động sau khi file có trên default branch.
- `verify-release.yml` và `verify_github_preview_release.sh` đóng gate sau upload
  bằng public API/download không Authorization. Lượt hiện tại xác minh lại
  `v1.1.0-preview.1`, exact commit/run/năm asset, API digest, checksum/manifest và
  Debian/PE32 signature; sai expected commit/tag fail closed.
- GitHub Private Vulnerability Reporting đã bật; `.github/SECURITY.md` hướng dẫn
  gửi báo cáo riêng tư và cấm đưa credential vào public issue.
- `scripts/agent/check.sh full` là quality gate canonical; baseline hiện có 106 test,
  analyze/format cả device integration source nhưng không tự boot virtual device.
- `scripts/supabase/` giữ remote contract, backup, health, restore và off-host harness.
- Scheduled restore contract nằm trong full gate; production systemd timer/health
  đã pass với atomic evidence và shared backup lock.
- `scripts/agent/linux_e2ee_operator.sh` giữ service-role key ngoài repository và
  ngoài client process, tạo isolated user, chạy Flutter E2EE trong Ubuntu/private
  keyring rồi xóa user và xác minh cleanup. Đây là protected operator gate, không
  đưa production service-role key vào GitHub Actions.

Chỉ đổi trạng thái ở file này khi có test hoặc runtime evidence tái hiện được.
