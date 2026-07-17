# Hướng dẫn phát triển

## Điều kiện cần

- Flutter stable và Dart SDK tương thích `pubspec.yaml`.
- Git và toolchain của platform đích.
- Supabase project không phải production để chạy luồng auth/sync.
- Xcode với Swift Package Manager cho iOS/macOS.

Kiểm tra máy:

    flutter doctor -v
    scripts/agent/doctor.sh

## Thiết lập lần đầu

1. Tạo public client configuration local:

       cp .env.example .env

2. Điền giá trị development:

       SUPABASE_URL=https://your-project.supabase.co
       SUPABASE_PUBLISHABLE_KEY=your-publishable-key
       PASSWORD_RECOVERY_URL=https://auth.example.com/reset-password/
       ALLOW_INSECURE_PLAINTEXT_SYNC=false

3. Tải dependency và generate Injectable:

       flutter pub get
       dart run build_runner build

4. Chọn thiết bị và chạy:

       flutter devices
       flutter run --dart-define-from-file=.env

`.env` bị Git ignore và không phải Flutter asset. Không đặt service-role key, database password, SMTP credential, TOTP secret hoặc user token thật trong file này. Analyze, test và build có thể chạy không cần `.env`; bootstrap runtime cần Supabase define hợp lệ.

Có thể truyền trực tiếp trong CI/release:

    flutter build web \
      --dart-define=SUPABASE_URL=... \
      --dart-define=SUPABASE_PUBLISHABLE_KEY=...

Alias `SUPABASE_ANON_KEY` cũ chỉ còn là fallback chuyển tiếp; configuration mới phải dùng `SUPABASE_PUBLISHABLE_KEY`.

`ALLOW_INSECURE_PLAINTEXT_SYNC` phải giữ `false`. Chỉ đặt `true` trong non-release
build dùng dữ liệu tổng hợp để kiểm tra migration/compatibility; release build vẫn
khóa sync plaintext ở runtime dù define này bị truyền nhầm.

## Workflow hằng ngày

Trước khi sửa:

    git status --short --branch
    scripts/agent/context.sh
    scripts/agent/check.sh docs

Sau thay đổi Dart:

    dart format lib test
    scripts/agent/check.sh quick

Sau thay đổi auth, storage, sync, routing, DI, plugin hoặc platform:

    scripts/agent/check.sh full
    scripts/agent/build.sh host

Build target rõ ràng:

    scripts/agent/build.sh android
    scripts/agent/build.sh ios
    scripts/agent/build.sh macos
    scripts/agent/build.sh web
    scripts/agent/build.sh windows
    scripts/agent/build.sh linux

Script sẽ báo target không hỗ trợ trên host thay vì giả vờ thành công.

## Supabase backend harness

Phần có thể version control nằm trong `supabase/`:

- release/commit pin ở `supabase/UPSTREAM_PIN`;
- reverse-proxy overlay không chứa secret;
- migration schema/RLS;
- contract test ở `scripts/supabase/test_remote_contract.sh`.

Áp dụng migration vào fresh self-hosted database từ host operator:

    docker exec -i supabase-db \
      psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
      < supabase/migrations/20260717163000_create_synced_accounts.sql

Chạy remote contract test ngay trên server có stack `.env`:

    scripts/supabase/test_remote_contract.sh /path/to/supabase/.env

Test cần `curl`, `jq`, public endpoint, publishable key và service-role key. Service
role chỉ dùng tạo/dọn isolated user; không copy key về Flutter `.env`, không bật
`set -x` và không lưu response body ngoài temporary directory của script.

Sau backend change, chạy cả test official của release pin, contract test dự án và
`scripts/agent/check.sh full`. Xem rollout/backup trong `docs/DEPLOYMENT.md` và
`docs/operations/SUPABASE_LEGACY_BACKUP.md`.

Kiểm tra recovery web và container hardening:

    reset-password-web/test.sh

Script chạy JavaScript harness, build image, kiểm tra invalid/public config,
security header, loopback/no-log và xác nhận `.env` không lọt vào image.

Kiểm tra additive E2EE schema/RPC bằng PostgreSQL cô lập:

    scripts/supabase/test_encrypted_vault_migration.sh

Harness tạo temporary container/roles/auth stub, áp migration rồi test revision
1→2, conflict, anonymous denial và owner RLS; không dùng production database.

## Cấu trúc repository

    lib/
      main.dart
      app.dart
      core/
      features/
    test/
    assets/
    docs/
    scripts/agent/
    scripts/supabase/
    supabase/
    reset-password-web/
    android/ ios/ macos/ web/ windows/ linux/

`lib/injection_container.config.dart` được generate. Không sửa tay; thay annotation/module rồi chạy:

    dart run build_runner build

## Luồng thay đổi thường gặp

### Thêm hoặc sửa field tài khoản

1. Cập nhật entity, equality, `toJson` và `fromJson`.
2. Cập nhật use case, local round-trip và sync serialization.
3. Định nghĩa migration/backward compatibility.
4. Cập nhật UI import/edit/export.
5. Thêm test cho format cũ và mới.
6. Cập nhật `DATA_MODELS.md`, `SUPABASE_INTEGRATION.md` và `SECURITY.md`.

### Thêm route

Cập nhật `AppRoutes`/`AppRouter`, xác định public/protected/fail-closed behavior, thêm redirect test và cập nhật `SYSTEM_DESIGN.md`.

### Thay đổi dependency injection

Sửa annotation hoặc module, generate lại, rồi xác minh lifecycle. State dùng chung giữa feature phải là shared instance và được cấp bằng `BlocProvider.value` khi provider không sở hữu lifecycle.

### Thay đổi sync

Bắt đầu từ `SECURITY.md`, `SUPABASE_INTEGRATION.md` và ADR. Định nghĩa idempotency, conflict, deletion, migration và rollback trước implementation.

## Lưu ý theo platform

### Android

- Application ID: `app.hyperz.authenticator`.
- Baseline dùng AGP 9.0.1, Gradle 9.1, Kotlin 2.3.20 và JVM 17.
- Release task dừng ngay nếu thiếu một phần signing credential; debug build không
  cần release keystore.
- `allowBackup=false`; vẫn phải test secure-storage behavior trên thiết bị/API đại diện.

### iOS

- Bundle ID hiện giữ `app.hyperz.authenticator` để không đổi install identity.
- Plugin được resolve bằng Swift Package Manager; không còn CocoaPods integration.
- Đã có camera, photo library, Face ID usage description và keychain entitlement.
- Cần cài đúng iOS Simulator Runtime hoặc dùng thiết bị vật lý.
- Password recovery dùng Web canonical; cần deploy template/allow-list và email E2E.

### macOS

- Plugin được resolve bằng Swift Package Manager.
- Debug build dùng keychain mặc định để có thể ký ad-hoc; Release có keychain access group và cần signing identity hợp lệ.
- Sandbox đã bật network client và camera. Release cần xác minh local-auth, keychain, signing và notarization.

### Web, Windows và Linux

- Web không bật `local_auth`; scanner hỗ trợ camera nhưng không hỗ trợ analyze ảnh file.
- Windows hỗ trợ device authentication nhưng scanner plugin hiện không hỗ trợ camera.
- Linux chưa có local-auth hoặc scanner trong dependency hiện tại.
- Manual TOTP entry vẫn là đường dùng chung trên mọi platform.

## Debug an toàn

- Xem `secretKey`, URI `otpauth`, session, password và recovery material là credential.
- Không log email hoặc raw exception chứa request data theo mặc định.
- Chỉ dùng fixture tổng hợp và domain `.invalid`.
- Không chụp screenshot có secret thật.

## Dọn và generate lại

Chỉ clean khi chẩn đoán cache/generated state:

    flutter clean
    flutter pub get
    dart run build_runner build

`flutter clean` không thay thế việc tìm nguyên nhân build failure và không được dùng để xóa thay đổi platform của người khác.
