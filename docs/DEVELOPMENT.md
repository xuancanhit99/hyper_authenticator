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

## Dependency

    flutter pub outdated

Chỉ nâng package resolvable, đọc changelog plugin/platform và chạy `full` + build
matrix. `build_runner` 2.15.2 hiện không resolvable do Flutter test SDK pin `meta`.

## Backend operator boundary

Client repo không chứa server secret. Remote contract/backup script nhận operator
env path bên ngoài repository. Chạy script với `set -x` là vi phạm bảo mật.

Runbook: `docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md`.
