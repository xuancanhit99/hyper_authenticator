# Phát triển

## Yêu cầu

- Flutter stable/Dart theo `pubspec.lock` và CI.
- Xcode/Cocoa tooling cho iOS/macOS.
- Android SDK/JDK cho Android.
- Docker + PostgreSQL client cho backend migration harness.
- Node khi chạy Web/release harness.

Kiểm tra môi trường:

```bash
flutter doctor -v
scripts/agent/doctor.sh
```

## Bắt đầu task

```bash
git status --short --branch
scripts/agent/context.sh
```

Đọc `AGENTS.md`, `docs/PROJECT_STATUS.md` và tài liệu canonical của subsystem.
Không reset/format thay đổi không liên quan trong working tree.

## Dependency và codegen

```bash
flutter pub get
dart run build_runner build
```

Không sửa thủ công `lib/injection_container.config.dart`. Sau thay đổi annotation,
chạy codegen và để drift gate xác minh.

## Public runtime config

Tạo file local ignored, ví dụ `.env`:

```json
{
  "SUPABASE_URL": "https://supabase.example.com",
  "SUPABASE_PUBLISHABLE_KEY": "TEST_ONLY_PUBLIC_KEY",
  "PASSWORD_RECOVERY_URL": "https://authenticator.example.com/reset-password"
}
```

Chạy:

```bash
flutter run --dart-define-from-file=.env
flutter build apk --release --dart-define-from-file=.env
```

Không cần cloud thì chạy không có define; local TOTP vẫn hoạt động. File `.env`
không chứa SSH/compose/DB/SMTP/service-role credential. Dùng `.env.server` ignored
cho operator/server values; `scripts/agent/separate_local_env.sh` hỗ trợ tách file
legacy.

## Lệnh hằng ngày

```bash
dart format lib test integration_test tool
dart analyze
flutter test
scripts/agent/check.sh quick
```

Scope auth/storage/sync/routing/plugin/platform:

```bash
scripts/agent/check.sh full
```

Backend local:

```bash
scripts/agent/check.sh backend
```

## Chạy target

```bash
flutter devices
flutter run -d <device-id> --dart-define-from-file=.env
flutter build apk --release --dart-define-from-file=.env
flutter build ios --release --no-codesign --dart-define-from-file=.env
flutter build macos --release --dart-define-from-file=.env
flutter build web --release --dart-define-from-file=.env
flutter build windows --release --dart-define-from-file=.env
flutter build linux --release --dart-define-from-file=.env
```

Chỉ target hiện tại mới chạy được trên host phù hợp; Windows/Linux hosted CI giữ
evidence cho hai platform đó.

## Chrome Extension development

Foundation MV3 có entrypoint riêng và không dùng `.env.server`:

```bash
scripts/agent/build_chrome_extension.sh .env
```

Kết quả:

- `build/chrome-extension/unpacked`: load qua `chrome://extensions` → bật
  Developer mode → **Load unpacked**;
- `build/chrome-extension/hyper-authenticator-<version>-chrome-extension.zip` và
  file `.sha256`: preview package, manifest ở root.

Không load extension với local vault thật ở giai đoạn foundation. Dùng Chrome
profile test riêng và test account/secret fixture không production. Harness
reject remote executable code/PWA worker/source map/debug artifact; nó không
thay thế clean-profile, restart, tamper và auth-sync acceptance.

CanvasKit fallback font cũng phải self-hosted: builder đóng gói Noto Sans WOFF2
cùng OFL license và ghi `fontFallbackBaseUrl: 'font-fallbacks/'` vào bootstrap.
Không thêm `fonts.gstatic.com` vào CSP để xử lý warning font.

## Android signing

Keystore nằm ngoài repository. Local `android/key.properties` là ignored và chứa
path/alias/password local; GitHub Actions dùng encrypted secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

Không upload keystore vào artifact. Giữ ít nhất hai encrypted/offline backup và
ghi fingerprint certificate ngoài secret store.

## Apple signing

Chọn đúng Team/bundle identity trong Xcode. Development/Ad Hoc install cần
certificate + provisioning profile khớp registered device. App Store/TestFlight
cần Apple Developer distribution credentials riêng. Không commit `.p12`, private
key hoặc profile.

## Account-sync integration

Integration test mutation chỉ dùng isolated account. Operator tạo credential,
runner truyền qua file/env tạm, rồi cleanup remote user/row:

```bash
scripts/agent/mobile_account_sync_operator.sh
scripts/agent/linux_account_sync_operator.sh
```

Client process không được nhận service-role key. Smoke cover upload, fresh-device
download và deletion tombstone; operator tạo/xóa isolated user.

## Supabase schema

Migration canonical:

```text
supabase/migrations/20260804000000_create_account_managed_sync.sql
supabase/migrations/20260805000000_add_account_sync_realtime_signal.sql
supabase/migrations/20260805010000_fix_account_sync_realtime_authorization.sql
```

Local contract:

```bash
scripts/supabase/test_account_sync_migration.sh
```

Migration đầu là breaking reset lịch sử; hai migration Realtime sau đó là
additive và phải được apply theo thứ tự timestamp.
Không apply lên production từ IDE/local shell trước khi hoàn tất backup + restore
rehearsal theo deployment runbook.

## Debug an toàn

- Không `print` account entity, TOTP payload, auth credential hoặc full URI.
- Dùng redacted state/failure message.
- Không paste credential vào command history nếu script hỗ trợ `--*-file`.
- Xóa isolated test user/file temp sau runtime test.
- `.env`, `.env.server`, signing material và build artifact không thuộc commit.

## Bàn giao

Mỗi task ghi kết quả, file thay đổi, behavior/data contract, command đã chạy,
rủi ro còn lại và xác nhận thay đổi không liên quan được bảo toàn.
