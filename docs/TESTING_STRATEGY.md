# Chiến lược kiểm thử

## Mục tiêu

Ưu tiên chống lộ TOTP credential, mất vault, bypass app lock, cross-tenant access
và cloud overwrite khi conflict. Build pass không thay thế runtime/data contract test.

`scripts/agent/build.sh <target> <env-file>` chạy release-config validator trước
build. Bỏ `<env-file>` chỉ chứng minh compile, không chứng minh bootstrap config.

## Gate canonical

| Scope | Command |
|---|---|
| Docs | `scripts/agent/check.sh docs` |
| Dart/UI | `scripts/agent/check.sh quick` |
| Auth/storage/sync/DI/platform | `scripts/agent/check.sh full` |

`full` phải pass generated-code drift, format (gồm source `integration_test`),
analyze, platform manifest/entitlement contract, Flutter test và encrypted
PostgreSQL migration contract. Nó không tự boot emulator/simulator.

## Coverage hiện tại

106 Flutter tests bao phủ:

- router/auth/logout/offline-local-vault boundary;
- post-login navigation trực tiếp hoặc return an toàn về Settings, stale null auth
  event không ghi đè session hiện tại và auth log redaction;
- repository/BLoC/widget flow revoke session khác: typed failure, confirmation,
  loading chống submit lại và không làm mất authenticated state;
- main-navigation URL/tab mapping và deep-link return qua app-lock bootstrap;
- TOTP URI/validator, countdown nhiều period và lifecycle resume;
- local vault migration, concurrent mutation, corruption rollback, atomic replace
  và generation compaction;
- local-auth startup lock, relock và plugin-error fail closed;
- AES-GCM round-trip, tamper, wrong user, future format và recovery unwrap;
- secure key-store initialize/write/delete verification;
- encrypted setup/cancel/recovery/wrong key/sync/conflict/use-cloud/keep-local;
- recovery-key rotation success/cancel/concurrent conflict và ambiguous verify;
- vault-key rotation success/cancel/conflict, stale-device recovery requirement,
  post-commit transport/verify ambiguity và secure-storage write failure;
- recovery dialog tự quản lý controller, đóng route an toàn khi submit hoặc hủy;
- recovery key bị redact khỏi BLoC event/state transition string;
- remote encrypted mapper, revision response và conflict mapping;
- plaintext bridge release guard.
- public runtime config: HTTPS-only, key role, recovery URL và release plaintext flag.
- Web unavailable tile không hứa đăng nhập/cloud sync khi capability bị tắt.
- Primary auth/accounts UI dùng label tiếng Việt và không quay lại các label tiếng Anh
  cũ; app locale runtime bị khóa ở `vi` với Material/Widgets/Cupertino delegate,
  Web source cũng khai báo document language `vi`.
- Scanner pending permission không còn là màn hình đen; permission denied có
  thông báo, retry và đường quay lại nhập thủ công bằng controller giả không gọi camera.

## Remote contract

Production/staging test dùng isolated user và tự cleanup:

- encrypted RLS/RPC contract: 20 checks, gồm atomic ciphertext/wrapped-key rotation,
  hai session cùng user, revoke session cũ, RLS/RPC chặn JWT cũ ngay và session
  hiện tại tiếp tục hoạt động;
- password recovery token contract: 8 checks;
- Studio network/upstream/Basic Auth contract;
- backup checksum/catalog/tar validation;
- full restore vào database tạm + schema/FORCE RLS probe;
- public Auth health load budget: 100 request, concurrency 10, 100% HTTP 200,
  p95 tối đa 1 giây và single-request tối đa 2 giây.

Android Pixel AVD còn xác minh SDK thật gọi bulk revoke: isolated user có hai
session, UI xác nhận action, session count giảm 2→1, current session vẫn ở Settings
và test user/row/app data được cleanup.

Device integration smoke dùng fixture isolated và explicit destructive opt-in đã
pass trên Android Pixel AVD và iOS 26.5 Simulator. Suite kiểm tra bootstrap với
public config, thêm account qua UI, secure-storage round-trip, lifecycle
foreground/hidden, BLoC reload, chuyển Settings/Accounts và local-vault cleanup.
Runner chỉ chấp nhận Android emulator hoặc iOS Simulator; thiết bị thật và macOS
bị từ chối để không chạm vault người dùng.

Linux CI dùng cùng behavioral suite nhưng chạy trong private D-Bus Secret Service,
Xvfb và XDG sandbox mode 0700. Harness chỉ chạy khi `CI=true`, kiểm tra keyring
trước khi boot app và xóa toàn bộ sandbox bằng trap. Run `29643037143` xác minh đủ
phase add, libsecret round-trip, lifecycle, reload, navigation và cleanup trên x64.
Riêng gate behavioral này là headless runtime evidence; package transition được
kiểm tra bằng gate tách biệt dưới đây và cả hai vẫn chưa thay desktop/distro matrix.

Authenticated E2EE Linux gate dùng ba lớp fail-closed:

- operator wrapper nhận file secret mode 0600 nằm ngoài repository, tạo user
  `@example.invalid` qua admin API rồi luôn xóa và probe 404;
- container wrapper chỉ archive tracked/untracked non-ignored source, public config
  và credential của isolated user vào Ubuntu 24.04 pin digest;
- inner harness từ chối service-role key, gỡ test credential khỏi environment
  trước Flutter process, dùng private Secret Service/XDG sandbox và chỉ log phase cố định.

Hai lượt ngày 18-07-2026 đi qua production Supabase: setup revision 1, local sync
revision 2, fresh-device recovery, recovery-key rotation revision 3 với key cũ bị
reject, vault-key rotation revision 4 với key trước rotation bị reject và recovery
cuối. Operator cleanup pass; DB probe sau cùng có 0 matching user và 0 vault row.
Runtime này là Linux arm64 debug trong container, không thay signed/package runtime.

Debian packaging gate sinh dependency trực tiếp từ mọi ELF bằng `dpkg-shlibdeps`,
thêm explicit `libegl1`, `libgles2`, `libgl1` vì Flutter dùng `dlopen`, từ chối
env/source-map/debug artifact, kéo `gnome-keyring` làm Secret Service provider và
tạo SHA-256. Ubuntu 24.04 container sạch
cài package baseline metadata, launch installed release, nâng lên `1.1.0+10`, giữ
XDG sentinel, launch lại rồi remove package trong khi user data còn nguyên. Gate
cũng khóa archive root và container `/` ở mode 0755. Nó chứng minh package-level
transition, không chứng minh migration từ binary/data của một release lịch sử thật.

Distro matrix cài cùng current `.deb` trên Ubuntu 22.04/24.04 và Debian 12/13,
yêu cầu package tự kéo `gnome-keyring`, probe private Secret Service rồi giữ app
sống trong cả Xvfb và Weston Wayland headless. Lượt Docker arm64 ngày 18-07-2026
đã tái hiện lỗi thiếu `libEGL.so.1` rồi `libGLESv2.so.2`; package sau fix pass
toàn bộ X11/Wayland matrix. Hosted amd64 và KDE login/unlock/physical desktop vẫn
là bằng chứng tách biệt.

Remote script cần service-role key nên chỉ chạy trong protected operator context,
không trong untrusted fork CI.

## Build matrix

| Target | Gate |
|---|---|
| Android | Debug build mỗi CI; signed release trước store |
| iOS | Simulator build mỗi CI; signed archive + device/TestFlight trước store |
| macOS | Unsigned compile CI; signed runtime + notarized release trước phân phối |
| Web | Configured release + hardened image contract + CSP/runtime `lang=vi` browser smoke |
| Windows | Hosted local-vault runtime + historical `1.0.0+9` vault-upgrade harness + configured x64 + NSIS install/launch/metadata-upgrade/uninstall retention; installer/checksum được phép lên GitHub Preview unsigned; physical device/signing trước stable |
| Linux | Hosted amd64 configured x64 + historical `1.0.0+9` upgrade + private-keyring runtime + `.deb` transition + Ubuntu/Debian X11/Wayland matrix; package/checksum được phép lên GitHub Preview unsigned; KDE/login/signed runtime trước stable |

## GitHub Preview gate

`scripts/agent/github_preview_release.sh` chỉ publish khi tag dạng preview khớp
`pubspec.yaml`, trỏ đúng checkout và có workflow `CI` push thành công của chính tag.
`check_github_preview_assets.sh` yêu cầu đúng một `.deb`/checksum và một Windows
setup/checksum, từ chối env/source-map/debug symbol rồi tạo manifest SHA-256 tổng.
`verify_github_preview_release.sh` là post-upload gate độc lập credential: public
API phải chứng minh non-draft pre-release, annotated tag tới exact commit, successful
CI run đúng tag/commit và release note provenance; public download phải có exact
năm asset, khớp GitHub digest, individual checksum, manifest tái tạo và Debian/PE32
signature. Publisher chuyển gate lỗi về draft; workflow `Verify Public GitHub
Preview` chạy trên release `published` hoặc manual tag. Workflow dùng verifier từ
default branch nhưng lấy package version đã đóng băng trong public release note,
nên release cũ không phụ thuộc `pubspec.yaml` hiện tại.

Regression tối thiểu của harness:

- fixture hợp lệ tạo đúng năm release asset;
- checksum sai, sai version, asset thừa thuộc denylist hoặc output không rỗng đều fail;
- explicit historical package-version override cho public release cũ phải pass;
- release tồn tại, repository private, tag/HEAD mismatch hoặc tag CI chưa xanh đều
  fail trước lệnh publish;
- sau publish, tải asset qua public GitHub URL và xác minh `SHA256SUMS.txt`.
- sai expected commit/tag hoặc public metadata/provenance/asset digest đều fail
  trước khi release được xem là hoàn tất.
- canonical full gate chạy syntax/invalid-input/no-Authorization/static draft-
  rollback contract mà không phụ thuộc network; live public gate nằm trong
  publisher và workflow riêng để không khóa development trước khi có tag mới.

## Regression rule

- Bug phải có test fail trên behavior cũ nếu có thể tái hiện deterministically.
- Storage/security change phải test success, interruption/corruption và rollback.
- Remote schema change phải có migration test + isolated cross-user contract.
- Field persist phải có round-trip test, không silently default.
- UI conflict/destructive operation cần widget/integration coverage khi ổn định.

## Secret hygiene trong test

- Không dùng secret/JWT/recovery key thật.
- Không snapshot full network request có credential.
- Temp file permission 0700/0600 và cleanup bằng trap.
- Email test dùng domain `.invalid`; user được xóa sau test.
- Không bật shell tracing cho operator harness.
- `scripts/agent/check_secrets.sh` scan toàn bộ Git history và staged diff bằng
  Gitleaks; CI tải binary đã pin sau khi xác minh SHA-256.
- `web-deployment/test.sh` build image từ tar allowlist rồi kiểm tra CSP/cache/SPA,
  read-only, dotfile, no-log và không chứa `.env`.
- `scripts/agent/build_linux_container.sh` archive committed ref vào Ubuntu 22.04
  pin digest, clone đúng Flutter 3.44.6 và xác minh Linux executable.
- `scripts/agent/linux_integration.sh` từ chối non-Linux/non-CI, dùng XDG sandbox,
  private Secret Service và explicit vault-reset opt-in trước local-vault smoke.
- `scripts/agent/package_linux_deb.sh` scan ELF dependency, khóa archive mode và
  tạo `.deb` + SHA-256; `linux_package_smoke.sh` chỉ mutate Ubuntu container tạm.
- `linux_distro_matrix.sh` chỉ nhận GitHub-hosted Linux runner, cài current package
  vào bốn container pin digest và tách toàn bộ XDG/Secret Service khỏi host.
- `scripts/agent/linux_e2ee_operator.sh` tách operator/client credential, gọi
  container/private-keyring runtime và xác minh isolated user đã bị xóa. Production
  service-role key không được lưu ở GitHub Actions secret hoặc truyền vào Flutter.
- `scripts/supabase/test_auth_load_budget.sh` chỉ dùng public publishable key,
  không tạo user/payload và fail khi HTTP hoặc latency vượt budget.
- `windows_integration.ps1` và `windows_installer_smoke.ps1` chỉ nhận GitHub-hosted
  Windows runner tạm cùng explicit mutation opt-in; không chạy trên máy người dùng.
- `windows_historical_upgrade.ps1` pin source `1.0.0+9` cùng storage plugin 3.1.2,
  seed DPAPI map với account có non-default TOTP field rồi yêu cầu current app
  nhìn thấy, publish COW v2 và cleanup. Engine unit test bao phủ source vắng, atomic copy, marker,
  symlink, conflict byte-level và rollback giữa chừng.
- `install_nsis.ps1` pin NSIS version + archive SHA-256; package builder từ chối
  env/source-map/debug artifact và tạo checksum LF portable.

## Khoảng trống đã biết

1. Device integration bao phủ local vault/navigation/lifecycle trên Android
   emulator, iOS Simulator và GitHub-hosted Windows Server 2025; biometric/camera
   và secure-storage behavior trên thiết bị thật chưa được chứng minh.
2. Chưa có two-device physical E2EE test.
3. Chưa có mailbox SMTP/expired-link E2E.
4. Low-concurrency Auth budget đã enforce; chưa có long-duration soak hoặc
   production-scale workload test.
5. Windows/Linux unsigned package đủ điều kiện GitHub Preview nhưng chưa phải stable.
   Windows còn code signing và physical-device/Windows Hello. Linux còn KDE
   login-unlock/physical desktop và signed package E2EE runtime.
