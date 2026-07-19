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
PostgreSQL migration contract. Contract hiện gồm device-wrap two-phase enrollment,
legacy cutoff, server-only DEK verifier chống fake self-wrap, active-device binding,
exact-set rotation và atomic crypto revoke. Nó không tự boot emulator/simulator.

## Coverage hiện tại

186 Flutter tests bao phủ cả focused regression cho device enrollment, local
unwrap/proof trước confirm, generation-aware publish và exact-set rotation
preparation, cùng các nhóm sau:

- router/auth/logout/offline-local-vault boundary;
- post-login navigation trực tiếp hoặc return an toàn về Settings, stale null auth
  event không ghi đè session hiện tại và auth log redaction;
- repository/BLoC/widget flow revoke session khác: typed failure, confirmation,
  loading chống submit lại và không làm mất authenticated state;
- device registry model/identity-store/BLoC/widget: installation UUID round-trip,
  current marker, targeted confirmation, self-revoke/double-submit guard, failure
  giữ list và identifier redaction;
- main-navigation URL/tab mapping và deep-link return qua app-lock bootstrap;
- TOTP URI/validator, countdown nhiều period và lifecycle resume;
- local vault migration, concurrent mutation, corruption rollback, atomic replace
  và generation compaction;
- local-auth startup lock, relock và plugin-error fail closed;
- AES-GCM round-trip, tamper, wrong user, future format và recovery unwrap;
- secure key-store initialize/write/delete verification;
- encrypted setup/cancel/recovery/wrong key/sync/conflict/use-cloud/keep-local;
- recovery-key rotation success/cancel/concurrent conflict và ambiguous verify;
- vault-key rotation success/cancel/conflict, surviving-device automatic unwrap,
  tampered wrap không persist DEK, revoked binding không giả thành recovery,
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
- Auth, account list và form thêm account pass labeled tap target, Android 48×48
  và WCAG text-contrast guideline trên light/dark theme ở viewport 320×640/text
  scale 200%; regression test khóa password/search/copy semantics tiếng Việt,
  TOTP countdown và layout không overflow.
- Settings recovery import/key confirmation, sync conflict và session revoke dialog
  pass semantics + Android 48×48 + WCAG text-contrast guideline trên light/dark
  theme ở viewport 320×640/text scale 200%; raw recovery key không vào semantics
  tree, copy action có accessible name, import field obscured/autofocus/keyboard
  submit và destructive dialog mặc định Enter vào **Hủy**. Dialog content scroll
  được thay vì overflow ở text scale lớn.
- Keyboard regression phát Tab/Shift+Tab/Enter/Space/Escape: bao phủ login,
  register, update/recovery Auth form; theme/add/search/copy TOTP; manual
  add-account; recovery import/key confirmation, conflict và session dialog.
  Recovery-key confirmation chỉ tới action sau checkbox đã lưu và Escape trả hủy.
- Root privacy shield regression điều khiển lifecycle qua `inactive`, `hidden`,
  `paused`, `detached` và `resumed`; xác minh overlay che, bỏ focus, chặn pointer,
  loại sensitive label khỏi semantics tree và khôi phục state/interaction khi resume.
  Test bootstrap riêng giữ UI khả dụng khi desktop/headless có initial `detached`
  nhưng không phát `resumed`. Các test này chưa chứng minh native app-switcher
  snapshot hoặc active screenshot block.
- Add-account route regression chứng minh `AccountsLoaded` không tự đóng form;
  chỉ operation-specific success mới đóng route, không pop page cuối và state
  success không mang account/secret.
- Edit-account route regression chứng minh reload không tự đóng form, submit đang
  chạy không phát update lặp và chỉ `AccountUpdateSuccess` mới hoàn tất navigation.
  Success không thuộc form hoặc sai opaque operation token bị bỏ qua. GoRouter
  root trở về `/` thay vì pop page cuối; toàn bộ field TOTP không mặc định vẫn
  round-trip qua update request. Failure đúng token giữ form, mở lại submit và
  hiển thị lỗi. Mutation event/state string regression không để account identity
  hoặc secret xuất hiện trong entity, use-case param hay BLoC log representation.

## Remote contract

Production/staging test dùng isolated user và tự cleanup:

- encrypted RLS/RPC contract: 20 checks, gồm atomic ciphertext/wrapped-key rotation,
  hai session cùng user, revoke session cũ, RLS/RPC chặn JWT cũ ngay và session
  hiện tại tiếp tục hoạt động;
- device registry contract: 25 checks, gồm no-direct-table/anonymous, two-user/
  two-session isolation, server current marker, self/cross-tenant reject, targeted
  refresh/JWT revoke, current survival và cleanup 0 orphan;
- password recovery token contract: 8 checks;
- Studio network/upstream/Basic Auth contract;
- backup checksum/catalog/tar validation;
- full restore vào database tạm + schema/FORCE RLS probe;
- scheduled restore contract không Docker: due/skip, failure giữ evidence cũ,
  backup quá hạn, evidence mode/schema và systemd sandbox/timer;
- public Auth health load budget: 100 request, concurrency 10, 100% HTTP 200,
  p95 tối đa 1 giây và single-request tối đa 2 giây;
- Auth load pacing contract: sleep đúng giữa batch, không sleep sau batch cuối và
  từ chối interval âm trước network; dùng cho soak bảo thủ không tạo user/payload.
- NPM database credential contract chạy fake Docker boundary để khóa plaintext-env,
  `MYSQL_PASSWORD_FILE`/`MARIADB_PASSWORD_FILE`, command exit propagation, missing
  credential silent failure và symlink reject. Production read-only route matrix
  còn phải pass trước/sau maintenance; static contract không thay file-secret canary.

Android Pixel AVD còn xác minh SDK thật gọi bulk revoke: isolated user có hai
session, UI xác nhận action, session count giảm 2→1, current session vẫn ở Settings
và test user/row/app data được cleanup.

Device integration smoke dùng fixture isolated và explicit destructive opt-in đã
pass trên Android Pixel AVD và iOS 26.5 Simulator. Suite kiểm tra bootstrap với
public config, probe `write/read/readAll/delete` trực tiếp qua secure-storage,
thêm account qua UI, vault round-trip, lifecycle foreground/hidden, BLoC reload,
chuyển Settings/Accounts và cleanup vault/secure-storage/preferences trong
`finally`, kể cả khi bootstrap hoặc seed fail.
Runner chỉ chấp nhận Android emulator hoặc iOS Simulator; thiết bị thật và macOS
bị từ chối để không chạm vault người dùng.

Authenticated E2EE smoke trên Android AVD và iOS Simulator còn tạo hai Supabase
session, installation UUID và X25519 key độc lập. Sau khi cả hai active ở generation
1, primary session rotate exact wrap set; secondary giữ DEK cũ và phải tự unwrap
generation 2 rồi decrypt revision 4 không dùng HA1. Suite cũng ghi đè primary bằng
DEK cũ để khóa cùng regression, sau đó operator xóa isolated user và admin GET phải
trả 404. Đây là two-session native-process evidence, chưa phải hai thiết bị vật lý.

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

Production scheduled drill ngày 19-07-2026 restore backup
`supabase-20260718T100222Z`, pass checksum/catalog/full restore cùng schema/FORCE
RLS/active-session guard. Sau device-registry rollout, manual rehearsal từ backup
`supabase-20260719T060755Z` pass thêm registry table/privilege/RPC guard; probe sau
drill xác nhận 0 database `ha_restore_rehearsal_*`. Health systemd pass và cả
backup trước/sau migration có encrypted off-host copy.

## Build matrix

| Target | Gate |
|---|---|
| Android | Debug build mỗi CI; signed APK + runtime/upgrade gate trước GitHub Release; AAB/internal track khi mở Play Store |
| iOS | Simulator build mỗi CI; không public binary qua GitHub; signed archive + device/TestFlight trước phân phối |
| macOS | Unsigned compile CI; Developer ID + signed runtime + notarized package trước GitHub Release hoặc phân phối khác |
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

Web rollback contract dùng fake Docker/curl state machine để chứng minh confirmation
fail trước mutation, success đi previous→current và public failure kích hoạt
auto-restore exact original env/image mà không ghi đè evidence pass cũ. Live gate
không chạy trong CI: operator production phải cung cấp exact image/hash. Lượt
19-07-2026 đã rollback thật `1.1.0-ae1ab36` → `1.1.0-12fce73` rồi forward lại;
post-probe current image/health/hash và 5/5 public SPA route pass.

## Regression rule

- Bug phải có test fail trên behavior cũ nếu có thể tái hiện deterministically.
- Storage/security change phải test success, interruption/corruption và rollback.
- Remote schema change phải có migration test + isolated cross-user contract.
- Field persist phải có round-trip test, không silently default.
- UI conflict/destructive operation cần widget/integration coverage khi ổn định.
- Cryptographic protocol mới phải khớp official/pinned vector trước round-trip và
  tamper test. Device-wrap foundation hiện dùng RFC 9180/CFRG vector cho cả
  AES-128-GCM reference suite và AES-256-GCM suite được chọn; regression còn khóa
  delimiter-collision, exact canonical envelope, oversized input và X25519
  low-order public key.

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
- `test-production-rollback-contract.sh` không dùng Docker/network thật; fake live
  state bao phủ rollback/forward và failure auto-restore trong full gate.
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
  `test_auth_load_budget_contract.sh` giả lập network/sleep để khóa pacing trước
  khi dùng `LOAD_BATCH_INTERVAL_MS` trên production; slowest request chỉ báo UTC,
  DNS/TCP/TLS/TTFB/total timing, không báo URL/header/IP.
- `test_nginx_proxy_manager_timing_contract.sh` khóa exact health route, exact
  image digest pin, logrotate-compatible filename và tám timing field; cấm đưa
  request/client variable vào NPM timing log.
- `backup_nginx_proxy_manager.sh` tạo transactional least-privilege NPM database dump cùng
  config/app/Let’s Encrypt archive, checksum và retention 0700/0600; raw DB volume
  và access log không đi vào archive.
- `rehearse_nginx_proxy_manager_backup.sh` xác minh checksum/archive rồi restore
  vào exact pinned MariaDB image với network tắt; yêu cầu đủ user/proxy/certificate/
  setting table và cleanup container/sandbox.
- `rehearse_nginx_proxy_manager_upgrade.sh` clone app/certificate/database vào
  internal Docker network không host port, rồi khóa exact target version, API 200,
  Nginx syntax và 4/4 core table trước khi cleanup container/volume/network/sandbox.
- `test_nginx_proxy_manager_backup_contract.sh` khóa transactional/exclusion,
  exact image/database metadata, authenticated readiness, no-port canary và network
  isolation; ngăn quay lại `mariadb-admin ping` vốn có thể nhận nhầm temporary init server.
- `test_nginx_proxy_manager_route_matrix.sh` khám phá mọi enabled HTTP domain,
  fail khi có stream/wildcard chưa cover, khóa exact critical status và chỉ cho
  pre-existing 5xx qua protected hash/status exception; output không lộ domain.
- `prepare_nginx_proxy_manager_upgrade.sh` chạy route → fresh backup → restore →
  canary → route, normalized-compare candidate Compose và tạo checksum bundle mà
  không mutate production. Contract test cấm compose lifecycle command/file swap.
- `deploy_nginx_proxy_manager_upgrade.sh` chỉ nhận checksum maintenance bundle đã
  byte-match current Compose và exact current/target image. Nó recreate riêng app,
  khóa runtime/API/Nginx/full route sau deploy và tự rollback exact Compose/image
  nếu fail; contract cấm dừng/xóa MariaDB, network hoặc volume.
- `render_nginx_proxy_manager_file_secrets.py` có fixture khóa exact env transform,
  candidate không chứa credential, mode 0700/0600/0400 và mismatch redaction.
- `prepare_nginx_proxy_manager_file_secrets.sh` bắt buộc route/fresh backup/restore/
  exact canary trước private checksum bundle; contract cấm production Compose
  lifecycle mutation.
- `deploy_nginx_proxy_manager_file_secrets.sh` byte-match Compose + `.env`, khóa
  backup/image/manifest checksum, recreate DB trước app và yêu cầu API/Nginx/DB 4/4,
  secret mounts, no-plaintext-env, route/timer. Contract buộc mọi route/secret/config
  mutation nằm sau transaction boundary, khóa exact rollback DB/app, giữ route
  snapshot khi rollback fail, từ chối bundle stale trước mutation và cấm xóa
  network/volume/data.
- `hyper-auth-nginx-proxy-manager-routes.timer` chạy full redacted route matrix mỗi
  giờ, persistent qua reboot; contract khóa manifest path, explicit mutation flag
  và systemd sandbox không inject credential.
- `test_scheduled_restore_drill_contract.sh` dùng backup/rehearsal fixture tạm,
  không đọc Docker hoặc backup thật; full gate chạy contract này trên mọi platform.
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
   emulator, iOS Simulator và GitHub-hosted Windows Server 2025; Android/iOS còn
   pass direct secure-storage preflight và fail-safe cleanup. Biometric/camera
   và secure-storage behavior trên thiết bị thật chưa được chứng minh.
2. Chưa có two-device physical E2EE test.
   Linux sandbox, Android AVD và iOS Simulator đã pass lost-device-key HA1
   replacement + rotation; Android/iOS còn pass two-session survivor auto-unwrap.
   Chúng không thay physical-device hoặc independent cryptographic review.
3. Chưa có mailbox SMTP/expired-link E2E.
4. Low-concurrency Auth budget đã enforce. Soak đầu gần 19 phút đạt 900/900 và
   p95 292 ms nhưng fail do max 3.648 ms. Sau khi deploy NPM timing allowlist,
   correlated soak pass 900/900, p95 289/max 590 ms; NPM/upstream p95 28/25 ms,
   max 244/244 ms và 0 non-200. Slowest client request có NPM/upstream 70/67 ms,
   cho thấy phần lớn tail ở trước backend. Chưa có production-scale test.
5. Windows/Linux unsigned package đủ điều kiện GitHub Preview nhưng chưa phải stable.
   Windows còn code signing và physical-device/Windows Hello. Linux còn KDE
   login-unlock/physical desktop và signed package E2EE runtime.
6. Accessibility automation đã bao phủ Auth, account list, form thêm account và
   sensitive Settings recovery/conflict/session dialog với WCAG text-contrast
   gate light/dark cùng core keyboard traversal. Chưa thay TalkBack/VoiceOver
   runtime, keyboard audit toàn bộ Settings/main navigation, active screen capture
   hoặc audit focus visualization trên từng OS.
