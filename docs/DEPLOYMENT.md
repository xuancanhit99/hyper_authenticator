# Deployment

## Nguyên tắc

Mỗi platform được phát hành độc lập. Một artifact chỉ đủ điều kiện khi source commit,
runtime config, schema compatibility, test evidence, checksum và signing provenance
được ghi lại. Không dùng debug signing cho production.

## Release input

- Version hiện tại: `1.1.0+10`.
- Flutter: 3.44.6 stable.
- Public config qua `--dart-define-from-file=<protected-file>`.
- Supabase migration E2EE + active-session guard đã deploy và remote contract
  20/20 pass.
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
- cập nhật release note, privacy URL, support/security contact;
- tag đúng tested commit và tạo SHA-256 cho artifact.

## Android

Yêu cầu file `android/key.properties` ignored và upload keystore do owner quản lý.
Build script đã fail nếu release signing thiếu:

    flutter build appbundle --release \
      --dart-define-from-file=.env.production \
      --split-debug-info=build/symbols/android

Gate: Play App Signing/upload certificate, target SDK review, camera/biometric test,
backup policy, data safety form và upgrade test từ version trước.

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
và chỉ là release candidate. Gate trước phân phối công khai còn Windows code
signing certificate, xác minh chữ ký sau download, physical-device/Windows Hello,
và Auth HTTPS. Scanner bị ẩn theo thiết kế.

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
X11/Wayland matrix đã pass. Gate còn lại: KDE login/unlock/physical desktop, signed
package E2EE runtime, maintainer/support metadata và release-channel signing.
Local authentication/scanner bị ẩn theo thiết kế.

## Supabase rollout

1. Full verified backup và off-host encrypted copy.
2. Diff official upstream pin/compose/env; staging upgrade trước.
3. Apply additive encrypted snapshot migration rồi active-session guard migration
   theo thứ tự filename, bằng role owner `supabase_admin`.
4. Chạy official smoke + project remote contracts; phải chứng minh JWT của session
   vừa revoke bị RLS/RPC chặn nhưng session hiện tại vẫn hoạt động.
5. Deploy client chỉ ghi encrypted snapshot.
6. Theo dõi health/journal/revision conflict; không xóa compatibility table.
7. Rollback client bằng cách tắt sync capability/release, giữ local vault và
   encrypted row. Drop plaintext table chỉ qua migration riêng.

## Backup/rollback

Runbook: `docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md`.

- Daily local retention: 7.
- Encrypted off-host retention: 14.
- Restore rehearsal dùng database tạm, không overwrite production.
- Signing key, age identity và backup checksum phải nằm ngoài repo.

## Gate còn phụ thuộc owner/hệ thống ngoài

- Android upload keystore.
- Apple development/distribution certificate, profile và notarization credential.
- Windows code-signing certificate nếu yêu cầu.
- Store account, public privacy URL, support/security contact và metadata.
- Mailbox để xác minh SMTP delivery/expired recovery link.
- External alert destination và backup host độc lập nếu yêu cầu SLA.

Thiếu một gate không làm mất các phần đã hoàn thiện, nhưng platform đó chưa được
gọi là production release cho tới khi gate pass.
