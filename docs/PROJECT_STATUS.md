# Trạng thái dự án

Baseline được xác minh ngày **18 tháng 7 năm 2026** trên macOS 26.5.1.

## Kết luận hiện tại

Hyper Authenticator là ứng dụng Flutter TOTP local-first cho Android, iOS,
macOS, Windows, Linux và Web. Native client đã có encrypted cloud sync dùng
AES-256-GCM, recovery key do người dùng giữ, optimistic revision và atomic
publication qua Supabase RPC. Web vẫn chủ động tắt cloud sync vì browser storage
không có trust boundary tương đương platform secure storage.

Source, local data path, E2EE client/server contract, backup và backend health
harness đã đạt baseline kỹ thuật. Việc phát hành store vẫn cần credential thuộc
owner: Android upload keystore, Apple signing/notarization và Windows signing nếu
phân phối installer đã ký. Không mô tả app là đã phát hành production trước khi
các credential gate tương ứng pass.

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
| `flutter test` | 89 test pass |
| Platform configuration gate | Pass network/backup/signing/Keychain/ID |
| Release config validator | Pass với `.env` public hiện tại, không in key |
| Gitleaks full history | Pass sau exact allowlist RFC 6238 test vector |
| Android debug + Pixel AVD runtime | Pass build/install, Supabase auth, setup revision 1, recovery-key rotation revision 2, vault-key rotation revision 3 và fresh-device recovery về revision 3; dialog teardown không còn assertion |
| Web release + hardened Nginx image | Pass public TLS/proxy, serving contract, `/` + `/settings` browser runtime và console sạch |
| macOS debug compile unsigned | Pass; không phải runtime/signing evidence |
| iOS 26.5 simulator debug | Pass build và runtime launch với Supabase init |
| Android release | Fail closed đúng thiết kế vì chưa có upload keystore |
| macOS release | Bị chặn vì chưa có development/distribution certificate |
| Linux release compile | Pass `linux/arm64` với Flutter 3.44.6 trên Ubuntu 24.04 isolated |
| Windows release | Remote CI pass configured x64 bundle; artifact 14 ngày và 22/22 checksum pass; còn device/installer/signing gate trên Windows |

Build không có `--dart-define-from-file` chỉ chứng minh compile. Runtime/release
verification phải inject `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` và
`PASSWORD_RECOVERY_URL` bằng compile-time define.

## Data và security path đã triển khai

- TOTP URI chỉ nhận `otpauth://totp`; validate Base32, SHA1/SHA256/SHA512,
  digits 6–8 và period dương.
- Local vault dùng versioned copy-on-write generation, commit marker, rollback
  generation và compaction giữ hai generation hợp lệ gần nhất.
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
- Web Settings không mời đăng nhập để dùng cloud sync khi capability bị tắt.
- Logo dịch vụ và font Averta không rõ license đã bị loại khỏi release; UI dùng
  avatar ký tự render bằng code. Data contract không thay đổi vì logo không persist.

## Supabase production đã xác minh

- Pin upstream self-hosted nằm trong `supabase/UPSTREAM_PIN`; stack có 11 core
  container healthy và PostgreSQL 17.6.1.136.
- Public API qua HTTPS; Studio qua HTTPS + Basic Auth; Kong/Supavisor không mở
  trực tiếp ra Internet.
- `encrypted_vault_snapshots` chỉ cấp SELECT cho authenticated owner, bật và
  force RLS. Atomic RPC chỉ dùng `auth.uid()` và trả `PT409` khi revision lệch.
- Remote encrypted contract: 12/12 pass; recovery contract: 8/8 pass; Studio
  proxy/DNS/upstream/Basic Auth contract pass.
- Smoke load có API key: 100/100 HTTP 200 ở concurrency 10; p95 khoảng 0,38 giây,
  max khoảng 0,40 giây. Sau test 11 Supabase container vẫn healthy, RAM available
  khoảng 3,4 GiB và swap used khoảng 610 MiB.
- Health timer chạy mỗi 5 phút. Backup timer chạy hằng ngày, giữ 7 bản local.
- Backup gồm logical database, globals, quiesced Storage và sensitive config;
  có SHA-256, permission 0700/0600 và validation catalog/tar.
- Full restore rehearsal đã pass vào database tạm rồi tự động drop; xác minh
  `auth.users`, encrypted table và `FORCE RLS`.
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
5. E2EE v1 đã có DEK rotation để thu hồi khả năng đọc current snapshot của client
   tuân thủ, nhưng chưa có individual device/auth-session revocation, tombstone/
   history hoặc Web trust model. Backup cũ vẫn dùng key generation cũ.
6. Chưa có Flutter device/integration suite đầy đủ; secure storage/biometric/camera
   vẫn cần test trên thiết bị thật.
7. Windows build còn dựa trên CI. Windows installer/signing/device và Linux
   package/keyring/device smoke test chưa xong.
8. Privacy policy cần được host tại URL công khai và điền kênh support trước store submission.
9. Flutter Web đã pass TLS/reverse proxy và runtime smoke trên production domain;
   camera permission/QR scan vẫn cần browser-device smoke thực tế.

## Automation

- `.github/workflows/ci.yml` chạy secret history, docs/generated-code/format/
  analyze/test và compile Android, iOS simulator, macOS unsigned, Web, Windows,
  Linux. Windows job yêu cầu ba repository variables public rồi tạo configured
  bundle, manifest SHA-256 và artifact 14 ngày; macOS unsigned không thay thế
  signed runtime gate.
- `.github/dependabot.yml` kiểm tra Pub và GitHub Actions hằng tuần.
- `scripts/agent/check.sh full` là quality gate canonical.
- `scripts/supabase/` giữ remote contract, backup, health, restore và off-host harness.

Chỉ đổi trạng thái ở file này khi có test hoặc runtime evidence tái hiện được.
