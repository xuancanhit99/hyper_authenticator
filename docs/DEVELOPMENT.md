# Phát triển

## Yêu cầu

- Flutter 3.44.6 stable, Dart 3.12.x.
- Android Studio/JDK 17+ và Android SDK cho Android.
- Xcode 26.5 + matching iOS Simulator runtime cho iOS/macOS.
- Docker chỉ cần cho Supabase migration test local.
- `jq`, `curl`, `ssh`, `age` cho production operator harness tương ứng.

Chạy đầu tiên:

    flutter doctor -v
    flutter pub get
    scripts/agent/doctor.sh

## Cấu hình client

    cp .env.example .env

Điền public client config; không thêm service-role/server/SSH credential:

    SUPABASE_URL=https://api.example.com
    SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
    PASSWORD_RECOVERY_URL=https://auth.example.com/reset-password/
    ALLOW_INSECURE_PLAINTEXT_SYNC=false

Chạy app:

    flutter run --dart-define-from-file=.env

`.env` chỉ được Flutter đọc ở build time qua command flag, không load runtime và
không bundle như asset.

Validate theo đúng release contract mà không in key:

    dart run tool/agent/check_release_config.dart .env

Validator chỉ cho phép bốn nhóm public client config (có alias legacy
`SUPABASE_ANON_KEY`), HTTPS URL và publishable/legacy `anon` key. Server/operator
variable phải nằm ở file khác ngoài repository.

## Workflow AI Agent

Mỗi lượt bắt đầu:

    git status --short --branch
    scripts/agent/context.sh

Sau đó đọc `docs/PROJECT_STATUS.md`, canonical doc của subsystem và test/call site
lân cận. Công việc nhiều subsystem tạo task record từ `docs/tasks/TEMPLATE.md`.

Không reset/format thay đổi không liên quan. Không log secret hoặc full process env.

## Quality gate

Chỉ tài liệu:

    scripts/agent/check.sh docs

Dart/UI thông thường:

    scripts/agent/check.sh quick

Auth/storage/sync/DI/plugin/platform:

    scripts/agent/check.sh full

`full` chạy docs gate, generated-code drift, format, analyze, platform config,
Flutter tests và Supabase encrypted migration test local.

Secret history gate cần Gitleaks 8.30.1 hoặc tương thích:

    scripts/agent/check_secrets.sh

## Generated code

Sau khi đổi Injectable annotation/constructor:

    dart run build_runner build --delete-conflicting-outputs
    git diff -- lib/injection_container.config.dart

Không sửa generated file thủ công.

## Build

Compile smoke theo host:

    scripts/agent/build.sh host

Build có runtime config đã validate:

    scripts/agent/build.sh host .env
    scripts/agent/build.sh ios .env

Trên macOS không có signing identity, script dùng `xcodebuild` với environment
allowlist và code signing tắt để lấy compile evidence. Artifact đó không chạy được
Keychain và không được dùng như runtime/release evidence.

Linux compile cô lập từ committed ref, không mount workspace hoặc truyền `.env`:

    scripts/agent/build_linux_container.sh
    scripts/agent/build_linux_container.sh <git-ref>

Flutter Web production-serving contract:

    scripts/agent/build.sh web .env
    web-deployment/test.sh
    web-deployment/build-image.sh hyper-authenticator-web:test

Runtime-configured build:

    flutter build web --release --dart-define-from-file=.env
    flutter build apk --debug --dart-define-from-file=.env
    flutter build ios --simulator --debug --dart-define-from-file=.env
    flutter build macos --debug --dart-define-from-file=.env

Android/macOS/iOS store release cần signing credential; thiếu credential phải fail,
không fallback debug/unsigned.

## Test chọn lọc

    flutter test test/features/sync/encrypted_vault_sync_usecase_test.dart
    flutter test test/features/sync/vault_cipher_test.dart
    flutter test test/features/authenticator/authenticator_local_data_source_test.dart
    flutter test test/features/authenticator/local_auth_bloc_test.dart

Không thêm secret thật vào fixture. Dùng `TEST_ONLY_*` và UUID/email isolated.

## Device integration smoke

Suite local-vault kiểm tra bootstrap có config, thêm account qua UI, round-trip
secure storage, lifecycle foreground/hidden, BLoC reload, navigation và cleanup:

    scripts/agent/device_integration.sh \
      emulator-5554 .env --allow-test-vault-reset

Tham số đầu cũng có thể là UUID của iOS Simulator đang boot. Harness fail closed:

- chỉ chấp nhận Android emulator hoặc iOS Simulator mà host nhận diện được;
- từ chối thiết bị thật và target macOS;
- yêu cầu opt-in `--allow-test-vault-reset` vì suite thay toàn bộ local vault trên
  target bằng fixture rồi xóa fixture trong `finally`;
- không upload cloud snapshot, không dùng TOTP secret hoặc account thật.

Không nới guard để chạy trên thiết bị người dùng. Device test cho biometric/camera
phải dùng flow riêng, dữ liệu isolated và không được reset vault ngầm.

Linux CI chạy cùng suite trong Xvfb và private D-Bus Secret Service:

    CI=true scripts/agent/linux_integration.sh \
      /path/to/public-release-config.json --allow-test-vault-reset

Harness yêu cầu Linux, `dbus-run-session`, `gnome-keyring-daemon`, `secret-tool`
và `xvfb-run`; tạo XDG sandbox mode 0700, probe keyring, rồi cleanup bằng trap.
Nó từ chối chạy ngoài CI để không chạm keyring/vault của desktop người dùng.
GitHub workflow là entrypoint canonical cho headless behavior. Package transition
CI và representative desktop/distro matrix là hai gate tách biệt.

Windows CI chạy cùng integration test bằng guard riêng:

    ./scripts/agent/windows_integration.ps1 `
      -EnvFile C:\path\release-config.json `
      -Confirmation '--allow-test-vault-reset'

Script chỉ nhận `CI=true`, `GITHUB_ACTIONS=true`, `RUNNER_OS=Windows` và
`RUNNER_ENVIRONMENT=github-hosted`; không nới guard để chạy trên workstation.
Historical upgrade gate chạy trước local-vault smoke để profile còn sạch:

    ./scripts/agent/windows_historical_upgrade.ps1 `
      -EnvFile C:\path\release-config.json `
      -Confirmation '--allow-historical-vault-migration'

Script archive commit pin `8e381debfe680ac906de391b4d9274e49acf9c06`
(`1.0.0+9`), giữ lock `flutter_secure_storage_windows 3.1.2`, ghi fixture vào
AppData thật của hosted runner rồi chạy current integration test. Bản build tạm
chỉ thêm compile-definition cho `local_auth_windows 1.0.11` tương thích MSVC
14.51; storage source/metadata/plugin vẫn giữ nguyên. Guard từ chối
workstation/self-hosted runner và cleanup cả hai layout trong `finally`.

Sau configured release, `install_nsis.ps1` tải NSIS 3.12 đã pin checksum,
`package_windows_installer.ps1` tạo unsigned installer/checksum và
`windows_installer_smoke.ps1` kiểm tra install/launch/metadata-upgrade/uninstall
giữ AppData. Smoke chỉ nhận hosted runner tạm và explicit
`--allow-ephemeral-install`. Baseline dùng cùng bundle với version metadata thấp
hơn, không thay historical-release migration test.

Sau configured release build trên Linux, tạo Debian candidate:

    scripts/agent/package_linux_deb.sh \
      build/linux/x64/release/bundle build/linux/deb

Builder nhận version từ `pubspec.yaml`, phát hiện amd64/arm64 từ ELF, sinh Depends
bằng `dpkg-shlibdeps`, bổ sung `libegl1`, `libgles2`, `libgl1` vì Flutter nạp
ba loader đồ họa bằng `dlopen`, từ chối env/source-map/debug artifact, khóa
archive root 0755 và tạo file `.deb.sha256`. CI còn chạy:

    CI=true scripts/agent/linux_package_smoke.sh \
      baseline.deb current.deb --allow-container-package-install

Smoke chỉ install trong Ubuntu 24.04 container pin digest; nó xác minh desktop
entry, shared library, release launch, metadata upgrade, remove và XDG data retention.
Baseline dùng cùng tested bundle với version thấp hơn, nên không được dùng làm bằng
chứng migration từ một release lịch sử thật.

Current package tiếp tục chạy qua distro matrix pin digest:

    CI=true GITHUB_ACTIONS=true RUNNER_ENVIRONMENT=github-hosted RUNNER_OS=Linux \
      scripts/agent/linux_distro_matrix.sh \
      current.deb --allow-container-package-install

Matrix cài package trên Ubuntu 22.04/24.04 và Debian 12/13, kiểm tra dependency
được package tự kéo, desktop entry, private `gnome-keyring` Secret Service và
launch trong Xvfb. Script từ chối workstation/self-hosted runner. Gate này không
thay KDE/KWallet, Wayland hoặc physical desktop smoke.

## Linux authenticated E2EE runtime

Gate này mutate production Supabase bằng isolated user và chỉ dành cho protected
operator context. Tạo file operator ngoài repository, mode 0600:

    SUPABASE_PUBLIC_URL=https://api.example.com
    SERVICE_ROLE_KEY=<operator-only>

Sau đó chạy:

    chmod 0600 /secure/path/supabase-operator.env
    scripts/agent/linux_e2ee_operator.sh \
      .env /secure/path/supabase-operator.env \
      --allow-isolated-remote-user

Wrapper tạo user `.invalid`, chạy Ubuntu 24.04 pin digest với Flutter 3.44.6,
private D-Bus Secret Service/Xvfb và source allowlist, rồi xóa user và yêu cầu
admin GET trả 404. Client đi qua setup, sync, fresh-device recovery, recovery-key
rotation, vault-key rotation và final recovery. Tất cả local data/key nằm trong
container/XDG sandbox tạm.

Service-role key chỉ được dùng ở parent operator shell qua header file 0600; không
đi vào Docker environment, Flutter define, GitHub Actions secret, log hoặc binary.
Container chỉ nhận credential của user test tạm, gỡ chúng khỏi process environment
trước khi boot Flutter và xóa cùng container. Không chạy script với `set -x`.

Đây là authenticated debug runtime evidence theo kiến trúc host của Docker. Nó
không thay signed `.deb`, historical-upgrade hoặc distro/desktop matrix.

## Dependency

    flutter pub outdated

Chỉ nâng package resolvable, đọc changelog plugin/platform và chạy `full` + build
matrix. `build_runner` 2.15.2 hiện không resolvable do Flutter test SDK pin `meta`.

## Backend operator boundary

Client repo không chứa server secret. Remote contract/backup script nhận operator
env path bên ngoài repository. Chạy script với `set -x` là vi phạm bảo mật.

Runbook: `docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md`.
