# Deployment

## Nguyên tắc

Mỗi platform được phát hành độc lập. Một artifact chỉ đủ điều kiện khi source commit,
runtime config, schema compatibility, test evidence, checksum và signing provenance
được ghi lại. Không dùng debug signing cho production. Artifact chưa ký chỉ được
phát hành theo contract **GitHub Preview unsigned** của ADR-0010; không được gọi là
stable, signed hoặc store release.

## Release input

- Version hiện tại: `1.1.0+10`.
- Flutter: 3.44.6 stable.
- Public config qua `--dart-define-from-file=<protected-file>`.
- Supabase migration E2EE + active-session/device-registry guard đã deploy;
  encrypted contract 20/20 và targeted registry contract 25/25 pass.
- `ALLOW_INSECURE_PLAINTEXT_SYNC=false` bắt buộc.
- Service-role/SSH/SMTP/database credential không được đưa vào client define file.

## Preflight chung

    git status --short --branch
    scripts/agent/check.sh full
    scripts/agent/check_secrets.sh
    dart run tool/agent/check_release_config.dart .env.production
    flutter pub outdated
    git diff --check

Sau đó:

- xác nhận 11 Supabase container healthy;
- chạy encrypted/recovery/Studio contracts;
- xác nhận backup mới, checksum và restore rehearsal;
- rà secret/Cyrillic/asset license;
- xác nhận platform configuration gate có INTERNET/cleartext/backup/Keychain/ID;
- cập nhật release note và security reporting channel; privacy/support URL là gate
  bắt buộc trước stable/store release;
- tag đúng tested commit và tạo SHA-256 cho artifact.

## GitHub Releases — kênh binary ưu tiên

Trong giai đoạn hiện tại, GitHub Releases là kênh phân phối binary mặc định; app
store chưa nằm trên critical path. Mỗi platform vẫn phải vượt gate riêng:

| Platform | Kênh hiện tại | Điều kiện để thêm binary vào GitHub Releases |
|---|---|---|
| Windows x64 | Unsigned pre-release | Đã đủ gate preview; code signing + device test trước stable |
| Linux amd64 | Unsigned pre-release | Đã đủ gate preview; signed channel + physical desktop trước stable |
| Android | Chưa phát hành | App-signing keystore lâu dài, signed APK, emulator/device và upgrade gate; không cần chờ Play Store |
| macOS | Chưa phát hành | Developer ID, hardened runtime, notarization, staple và runtime test |
| iOS | Không phân phối public qua GitHub | Signing/provisioning và kênh Apple phù hợp |
| Web | Production URL | Deploy image độc lập, không đóng gói vào GitHub Release |

GitHub Preview chỉ gồm Windows x64 NSIS installer và Linux amd64 Debian package.
Tag phải có dạng `vX.Y.Z-preview.N`, khớp app version và trỏ tới commit có workflow
`CI` của chính tag pass toàn bộ. Android debug APK, Apple compile build và Windows
portable CI bundle không được publish.

Quy trình maintainer:

    git tag -a v1.1.0-preview.1 -m "Hyper Authenticator v1.1.0-preview.1"
    git push origin v1.1.0-preview.1
    gh run list --workflow ci.yml --branch v1.1.0-preview.1

Sau khi tag CI xanh, chạy workflow `GitHub Preview Release` trên default branch với:

- `release_tag`: tag preview đã test;
- `confirmation`: `PUBLISH_UNSIGNED_GITHUB_PREVIEW`.

Maintainer workstation tin cậy có thể chạy cùng fail-closed harness:

    scripts/agent/github_preview_release.sh \
      v1.1.0-preview.1 PUBLISH_UNSIGNED_GITHUB_PREVIEW

Harness xác minh repository public, tag/HEAD/version, successful tag CI, release
chưa tồn tại, exact artifact name, checksum và denylist env/source-map/debug file.
Nó chỉ tải artifact từ CI run của tag, tạo `SHA256SUMS.txt`, release note bắt buộc
và publish với GitHub pre-release flag. Sau publish,
`verify_github_preview_release.sh` cố ý không gửi Authorization và yêu cầu public
API/download pass exact release state, tag/commit/successful tag CI, năm asset,
GitHub digest, checksum/manifest cùng Debian/PE32 signature. Nếu gate lỗi, publisher
chuyển release về draft; nếu cả rollback API lỗi, command phát cảnh báo `CRITICAL`
và exit non-zero. Xóa hoặc chuyển pre-release về draft là rollback channel; không
xóa source tag hoặc local vault của người dùng.

Workflow `Verify Public GitHub Preview` chạy lại gate khi preview được publish và
cho phép manual verification theo tag sau khi workflow đã có trên default branch.
Workflow checkout verifier từ default branch, còn package version được đọc từ
release note đã đóng băng; vì vậy vẫn xác minh được preview cũ sau khi source tăng
version mà không tin local tag content làm provenance:

    scripts/agent/verify_github_preview_release.sh \
      v1.1.0-preview.1 xuancanhit99/hyper_authenticator

SMTP production chưa được cấu hình ở giai đoạn này và không chặn phát hành binary
qua GitHub. Release note phải nói rõ email khôi phục mật khẩu có thể chưa tới
mailbox thật; credential SMTP chỉ được đặt trên server, không đưa vào Flutter
`.env` hay GitHub Actions. Chỉ bỏ cảnh báo sau khi delivery và expired-link E2E
đã pass với mailbox thật.

## Android

Yêu cầu file `android/key.properties` ignored và keystore do owner quản lý. Source
hiện gọi file này là `upload-keystore.jks`, nhưng trước public APK owner phải chốt
key bên trong là Android **app signing key** lâu dài của kênh GitHub. Build script
đã fail nếu release signing thiếu:

    flutter build appbundle --release \
      --dart-define-from-file=.env.production \
      --split-debug-info=build/symbols/android

Gate cho signed APK trên GitHub: app-signing keystore, certificate fingerprint,
target SDK review, camera/biometric test, backup policy và upgrade test từ version
trước. Mọi GitHub APK update phải giữ cùng app signing key.

Nếu sau này mở Play Store và muốn người dùng cập nhật chéo giữa GitHub/Play, cấu
hình Play App Signing bằng chính app signing key đã dùng cho GitHub, sau đó mới tạo
upload key riêng cho artifact gửi lên Play. Nếu để Play tự sinh app signing key
khác, hai kênh sẽ có certificate khác và không còn upgrade-compatible. Data safety
form và internal track chỉ trở thành gate khi mở Play Store. Xem contract key chính
thức tại [Android app signing](https://developer.android.com/studio/publish/app-signing).

## iOS

    flutter build ipa --release \
      --dart-define-from-file=.env.production \
      --split-debug-info=build/symbols/ios

Gate: matching Xcode runtime, team/provisioning profile, Keychain/Face ID/camera
trên device, associated recovery link behavior, archive validation và TestFlight.

## macOS

    flutter build macos --release \
      --dart-define-from-file=.env.production \
      --split-debug-info=build/symbols/macos

Entitlement secure storage yêu cầu signing certificate; không tắt signing để né gate.
Phân phối ngoài store cần Developer ID, hardened runtime, notarization và staple.
`scripts/agent/build.sh macos` có thể compile unsigned trong môi trường CI đã lọc;
artifact đó chỉ chứng minh compile và không được chạy/phân phối như app hợp lệ.

## Web

    scripts/agent/build.sh web .env.production
    web-deployment/test.sh
    web-deployment/build-image.sh hyper-authenticator-web:1.1.0-<commit> linux/amd64

E2EE sync bị tắt theo capability. Deploy immutable artifact qua HTTPS với CSP,
`nosniff`, referrer/permissions policy phù hợp; smoke login/local TOTP/camera trên
browser hỗ trợ. Edge reverse proxy kết thúc TLS là lớp duy nhất phát HSTS; không
đồng thời bật HSTS trong container HTTP nội bộ. Không cache HTML/config lâu hơn
asset hashed.

Image Nginx pin digest, chạy non-root/read-only và chỉ nhận `SUPABASE_URL` public
để tạo CSP. Phải truyền cùng origin đã dùng lúc compile; mismatch làm request bị
CSP chặn. Build context dùng tar allowlist nên không chứa `.env`, source hoặc Git
metadata. Noto Sans fallback của Flutter và `zxing-wasm` scanner vẫn là external
runtime resource đã giới hạn origin trong CSP; self-host chúng nếu policy cấm CDN.
Đối số platform là bắt buộc trong quy trình production cross-build: server hiện
chạy `linux/amd64`, trong khi máy build Apple Silicon mặc định tạo `linux/arm64`.
Phải kiểm tra `docker image inspect <image> --format '{{.Architecture}}'` trước
khi chuyển image; health check không được dùng làm cơ chế phát hiện đầu tiên.

Source canonical là `web-deployment/docker-compose.production.yml`; bản cài trên
server nằm tại `/opt/stacks/hyper-authenticator-web/compose.yml`. Tạo file `.env`
mode 0600 cạnh compose với `WEB_IMAGE` đã pin theo commit và cùng `SUPABASE_URL`
HTTPS. Trước khi đổi image, giữ image cũ và tạo bản sao `.env` mode 0600. Sau đó chạy:

    docker compose -f compose.yml config --quiet
    docker compose -f compose.yml up -d
    docker inspect --format '{{.State.Health.Status}}' hyper-authenticator-web

Nếu container không `healthy` trong cửa sổ rollout, khôi phục `.env` đã sao lưu
và chạy lại `docker compose -f compose.yml up -d`. Chỉ xóa image cũ sau khi public
hash, route và header đã được xác minh; không in `SUPABASE_URL` khi thao tác `.env`.

Trước release Web quan trọng, chạy live rollback drill với exact current/previous
image và JS hash theo `web-deployment/README.md`. Harness preflight hai shadow
container, atomic rollback→forward, verify container/public artifact và auto-restore
original image nếu failure. Evidence/snapshot mode 0600 nằm trong stack directory;
không tạo evidence thủ công và không xóa previous image trước drill. Container bị
recreate nên cần maintenance window; gate không khẳng định zero downtime.

Container không publish host port; reverse proxy phải cùng external network
`proxy-network` và forward tới `hyper-authenticator-web:8080`. Nginx Proxy Manager
sở hữu certificate/redirect TLS cho `authenticator.hyperz.xyz`. Sau rollout phải
test `/`, `/settings`, `/privacy` nếu legal page đã publish, header bảo mật và
browser console trên public HTTPS origin.

## Windows

    flutter build windows --release --dart-define-from-file=.env.production

Windows CI chỉ tạo artifact runtime khi repository có ba Actions variables public:

- `SUPABASE_URL`;
- `SUPABASE_PUBLISHABLE_KEY`;
- `PASSWORD_RECOVERY_URL`.

Workflow pin `windows-2025`, validate config, khóa plaintext sync và chạy
historical `1.0.0+9` vault upgrade trước `windows_integration.ps1`; cả hai có
explicit mutation opt-in và chỉ nhận hosted runner tạm.
Sau configured x64 release, workflow tạo hai artifact theo commit và giữ 14 ngày:

- bundle cùng `SHA256SUMS.txt`;
- NSIS 3.12 per-user installer cùng file `.sha256` dùng LF, kiểm tra được từ
  Windows, macOS hoặc Linux.

NSIS tool ZIP được tải từ upstream chính thức, pin SHA-256 và xác minh
`makensis v3.12` trước khi compile. Installer mặc định vào
`%LOCALAPPDATA%\Programs\Hyper Authenticator`; uninstaller chỉ xóa program
directory, shortcut và uninstall metadata, không xóa local vault dưới AppData.
CI đã pass install, launch release, nâng metadata baseline lên `1.1.0+10`, launch
lại, uninstall và data-retention sentinel. Package baseline vẫn dùng cùng tested
bundle với version thấp hơn. Gate storage tách biệt archive source pin
`1.0.0+9`, ghi DPAPI storage bằng plugin 3.1.2, rồi yêu cầu current app đọc đủ
field và publish COW v2. Gate này đã pass trong run `29648450700` trước release
build và installer transition.

Artifact không chứa file config nguồn hoặc private server credential; public
runtime values vẫn được compile vào client theo thiết kế. Installer hiện **unsigned**
và chỉ đủ điều kiện cho GitHub Preview theo ADR-0010. Gate trước stable/signed
distribution còn Windows code-signing certificate, xác minh chữ ký sau download
và physical-device/Windows Hello. Auth dùng HTTPS; scanner bị ẩn theo thiết kế.

`local_auth_windows` 2.0.1 còn phụ thuộc `/await` experimental. Project hiện opt in
warning-suppression mà MSVC 14.51 yêu cầu để giữ native CI chạy được; đây không phải
signing bypass. Khi upstream bỏ `/await`, xóa define và bắt buộc chạy lại Windows
artifact/device gate trước release.

## Linux

    flutter build linux --release --dart-define-from-file=.env.production

Cross-compile evidence tái hiện được từ committed ref:

    scripts/agent/build_linux_container.sh

Configured x64 release và private libsecret keyring/Xvfb runtime đã pass trong CI.
Debian candidate và checksum:

    scripts/agent/package_linux_deb.sh \
      build/linux/x64/release/bundle build/linux/deb

`.deb` build baseline từ Ubuntu 22.04 để giữ glibc floor 2.34, khai báo explicit
EGL/GLES/GL loader + `gnome-keyring` provider và đã pass exact local Docker arm64
matrix trên Ubuntu 22.04/24.04 cùng Debian 12/13 với private Secret Service,
Xvfb và Weston Wayland. Clean Ubuntu package transition/data retention cũng pass.
Hosted amd64 historical `1.0.0+9` upgrade, clean package transition và Ubuntu/Debian
X11/Wayland matrix đã pass. Package unsigned chỉ đủ điều kiện cho GitHub Preview.
Gate trước stable/signed distribution còn KDE login/unlock/physical desktop,
signed package E2EE runtime, maintainer/support metadata và release-channel signing.
Local authentication/scanner bị ẩn theo thiết kế.

## Supabase rollout

1. Full verified backup và off-host encrypted copy.
2. Diff official upstream pin/compose/env; staging upgrade trước.
3. Apply additive encrypted snapshot, active-session guard rồi device-registry
   migration theo thứ tự filename, bằng role owner `supabase_admin`. Device-wrap
   migration chỉ apply sau khi client v2 artifact/local contract đã sẵn sàng;
   server-only DEK verifier nằm trong schema `private`. Mặc định backfill protocol
   0 nên chưa khóa legacy client cho tới target confirm.
4. Chạy official smoke + encrypted/device remote contracts; phải chứng minh JWT
   của targeted session bị RLS/RPC chặn nhưng session hiện tại vẫn hoạt động.
5. Deploy client chỉ ghi encrypted snapshot.
6. Theo dõi health/journal/revision conflict; không xóa compatibility table.
7. Rollback client bằng cách tắt sync capability/release, giữ local vault và
   encrypted row. Drop plaintext table chỉ qua migration riêng.

Device-registry rollback: bỏ client UI trước, khôi phục health/restore probe rồi
drop ba RPC/table bằng migration riêng. Apply/rollback schema không sửa encrypted
snapshot; auth session đã thu hồi không thể phục hồi, người dùng đăng nhập lại.

Device-wrap rollback trước activation: bỏ client v2 rồi drop RPC/table/nullable
session FK bằng migration riêng; giữ hai snapshot column additive. Sau khi
`device_wrap_version=1`, không downgrade về legacy RPC vì có thể làm lệch DEK và
wrap set; rollback phải tắt sync, giữ local vault/remote row và dùng HA1 recovery
trên client v2 đã biết generation. Auth session đã crypto-revoke không phục hồi.

## Backup/rollback

Runbook: `docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md`.

- Daily local retention: 7.
- Encrypted off-host retention: 14.
- Scheduled restore drill trigger hằng ngày nhưng chỉ restore tối đa mỗi 7 ngày;
  failure được retry ngày sau. Health fail nếu evidence quá 9 ngày.
- Restore rehearsal dùng database tạm, không overwrite production, dùng chung lock
  với backup và chỉ ghi atomic evidence sau full security probe pass.
- Signing key, age identity và backup checksum phải nằm ngoài repo.

Khi rollout automation, phải chạy một drill thật trước khi cài health script mới;
không tạo evidence thủ công để làm health xanh. Disable timer + khôi phục script
health/rehearsal là rollback code path; backup/data/evidence được giữ để audit.

## Gate còn phụ thuộc owner/hệ thống ngoài

- Android upload keystore.
- Apple development/distribution certificate, profile và notarization credential.
- Windows code-signing certificate cho stable/signed release.
- Store account, public privacy URL, support/security contact và metadata.
- Mailbox để xác minh SMTP delivery/expired recovery link.
- External alert destination và backup host độc lập nếu yêu cầu SLA.

Thiếu một gate không làm mất các phần đã hoàn thiện. GitHub Preview phải giữ nhãn
unsigned/pre-release; platform chỉ được gọi là stable production release sau khi
signing, representative-device và legal/support gate tương ứng pass.
