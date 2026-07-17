# Trạng thái dự án

Baseline được xác minh ngày **18 tháng 7 năm 2026** trên macOS 26.5.1.

## Tổng quan

Hyper Authenticator là ứng dụng Flutter alpha hướng tới Android, iOS, macOS, Windows, Linux và Web. Luồng TOTP local, authentication, app lock và sync thủ công đã có. Đợt hiện đại hóa hiện tại đã nâng toolchain/dependency, sửa các lỗi đúng đắn quan trọng, bổ sung test/CI và đưa ba target có thể chạy trên host hiện tại về trạng thái build được.

Ứng dụng **chưa sẵn sàng production** với cloud secret thật. Cloud sync plaintext hiện
bị khóa mặc định, chỉ có thể bật trong non-release bằng build flag nguy hiểm dành
cho migration/test và luôn bị khóa trong release; protocol phía sau vẫn plaintext,
xóa-rồi-chèn. E2EE/atomic snapshot primitives cùng additive schema đã có nhưng chưa
nối onboarding/client remote flow hoặc deploy staging.
Supabase schema/RLS đã có migration cùng cross-user contract test, nhưng control
này chỉ giới hạn authorization, không mã hóa TOTP secret.

## Baseline toolchain và dependency

- Flutter 3.44.6 stable, Dart 3.12.2.
- Dart constraint: `^3.12.0`.
- Phiên bản ứng dụng: `1.0.0+9`.
- Mọi direct dependency ở phiên bản mới nhất mà dependency solver của baseline này chấp nhận.
- `build_runner` giữ ở 2.15.1 vì 2.15.2 xung đột với version `meta` được Flutter test SDK pin.
- Lockfile đã nâng `passkeys_platform_interface` 2.8.0 lên 2.9.0; các package còn
  báo newer đều không resolvable trên SDK/constraint hiện tại.
- Apple runner dùng Swift Package Manager; CocoaPods integration và lockfile cũ đã được loại bỏ.

## Kết quả xác minh

| Kiểm tra | Kết quả |
|---|---|
| `flutter doctor -v` | Không có lỗi toolchain |
| `dart format --output=none --set-exit-if-changed lib test tool` | Pass |
| `flutter analyze` | Pass, không có diagnostic |
| `flutter test` | 41 test pass |
| Android `flutter build apk --debug` | Pass |
| Web `flutter build web --release` | Pass |
| macOS `flutter build macos --debug` | Pass |
| iOS simulator build | Chưa chạy được local vì thiếu iOS 26.5 Simulator Runtime |
| Windows/Linux build | Không thể build native trên macOS; CI đã có job tương ứng |

Test hiện có bao phủ thêm local-storage migration/recovery/fault injection,
countdown nhiều period, lifecycle resume, offline redirect/logout boundary,
plaintext-sync guard, stable-ID merge và E2EE crypto/key-store/remote mapper.
Chưa có device/integration test Flutter đầy đủ.

## Supabase self-hosted đã xác minh

- Fresh deployment dùng Docker release `self-hosted/v0.7.0`, commit pin trong `supabase/UPSTREAM_PIN` và PostgreSQL 17.6.1.136.
- 11 core service healthy: Studio, Kong, Auth, PostgREST, Realtime, Storage, imgproxy, postgres-meta, Edge Runtime, PostgreSQL và Supavisor.
- Public API đi qua reverse proxy HTTPS; Kong và hai Supavisor port chỉ bind loopback. Logs/Analytics chưa bật; host có 7,8 GB RAM và chưa có load-test headroom. Keycloak VNPAY dùng `mem_limit` 3 GiB, reservation 1 GiB, JVM heap khởi tạo 25%/tối đa 65% theo limit container; sau cold start, host có khoảng 3,6 GB available.
- Host cleanup ngày 17 tháng 7 năm 2026 đưa disk từ 93% xuống 67%, còn khoảng 24 GB; Docker không còn cache reclaimable. Sau đó Vault MTLS POC được xóa theo yêu cầu owner, swap giảm còn khoảng 1,2/2 GB. SSH log level đã hạ từ DEBUG3 xuống INFO, chỉ cho phép public key và system journal bị giới hạn 1 GB/14 ngày.
- Legacy data/config/Storage đã backup có checksum ngoài repository; instance mới không import dữ liệu cũ.
- `synced_accounts` có migration, grant CRUD tối thiểu, force RLS và bốn owner policy.
- Smoke test official qua public endpoint: 35 pass; API key/JWKS/asymmetric Auth: 43 pass; RLS contract: 17 pass.
- Session JWT mới dùng ES256; legacy HS256 verification vẫn pass để hỗ trợ transition.
- Sau test/cleanup: Auth user/audit, Storage bucket/object, Realtime message và `synced_accounts` đều 0 row.

Runbook và giới hạn restore nằm trong [Backup Supabase legacy](operations/SUPABASE_LEGACY_BACKUP.md).

## Ma trận platform

| Platform | Trạng thái | Ghi chú |
|---|---|---|
| Android | Đã build local | Camera QR, image import và device authentication được bật |
| iOS | Đã cấu hình | SwiftPM, entitlement và usage description đã cập nhật; cần runtime/thiết bị để xác minh |
| macOS | Đã build local | Sandbox network/camera đã cấu hình; release signing/keychain cần xác minh |
| Web | Đã build local | Camera QR được hỗ trợ; không bật local authentication |
| Windows | CI build | Nhập thủ công hoạt động theo thiết kế; scanner bị ẩn vì plugin không hỗ trợ |
| Linux | CI build | Nhập thủ công hoạt động theo thiết kế; scanner và local authentication bị ẩn |

Có artifact build không đồng nghĩa platform đã đủ điều kiện phát hành; release signing, installer, permission và kiểm thử thiết bị vẫn theo [Deployment](DEPLOYMENT.md).

## Cải tiến đã áp dụng

- Cấu hình Supabase chuyển từ asset `.env` sang compile-time `dart-define`.
- Gỡ dependency không dùng; nâng toàn bộ direct dependency có thể nâng.
- Parse TOTP tập trung, validate Base32/algorithm/digits/period và không log QR secret.
- Giữ nguyên algorithm, digits và period khi tạo record có UUID.
- Logout không còn xóa toàn bộ TOTP local.
- Auth, account và sync dùng cùng shared BLoC instance.
- App lock fail closed khi authentication lỗi và relock khi app rời foreground.
- Ẩn scanner/local-auth trên platform plugin không hỗ trợ.
- Sửa truy vấn `hasRemoteData` dùng đúng `account_id`.
- Map remote row sang snake_case, giữ đủ algorithm/digits/period khi round-trip.
- Thêm migration `synced_accounts`, grant tối thiểu, force RLS và isolated cross-user test.
- Làm mới Supabase self-hosted, rotate toàn bộ secret/key và bật asymmetric JWT/JWKS.
- Lỗi merge không còn bị nuốt rồi tiếp tục upload.
- Android nâng Gradle/AGP/Kotlin/JVM; Apple chuyển hoàn toàn sang SwiftPM.
- Thêm CI đa nền tảng, Dependabot và build harness cho AI Agent.
- Khóa cloud sync plaintext mặc định ở cả BLoC và remote data-source boundary.
- Countdown dùng Unix epoch và `period` riêng của từng account; code được cache theo time step.
- Local vault dùng versioned copy-on-write manifest/commit, fallback generation và legacy recovery.
- Merge compatibility dùng stable `account_id`, giữ ID khi persist và không còn chờ BLoC qua completer.
- Recovery web nhận runtime public config, chạy read-only/non-root, không log session và hỗ trợ one-time `token_hash`.
- Android release build fail nếu thiếu signing thay vì fallback debug.
- Local vault hoạt động offline không cần Supabase session; logout giữ app lock.
- Web recovery được chọn làm canonical surface, có client redirect config và
  self-hosted email template version control.
- AES-256-GCM snapshot/AAD, DEK wrapping, recovery key và secure key-store primitive
  đã có regression test; migration v2 có atomic revision/RLS harness.
- Source dùng Apache License 2.0; asset/trademark vẫn cần provenance audit.

## Release blocker còn lại

### Bảo mật và dữ liệu

1. Table compatibility vẫn chứa plaintext nếu dangerous bridge được dùng; release
   bridge khóa. E2EE v2 chưa nối SyncBloc/onboarding hoặc deploy.
2. Upload cloud xóa snapshot cũ rồi chèn snapshot mới, không atomic và không idempotent.
3. Merge đã dùng stable `account_id` và local-wins khi trùng ID, nhưng chưa có revision conflict protocol hoặc tombstone.
4. Schema plaintext hiện tại là compatibility bridge; build client cũ dùng camelCase không tương thích backend mới.
5. Chưa có backup định kỳ, off-host encrypted copy, monitoring/alerting và RAM/swap headroom đã được kiểm chứng dưới tải cho Logs/Analytics.
6. Secure storage trên Web có threat model khác native và cần review riêng.

### Tính đúng đắn và sản phẩm

1. Local vault offline-first đã hoạt động; multi-profile local không thuộc scope,
   nên các Supabase session trên cùng OS profile dùng chung vault sau unlock.
2. Web recovery đã được chọn/template hóa nhưng redirect allow-list, Auth template
   deployment và email-link E2E chưa chạy.
3. Local-storage v2 chưa có compaction/retention và chưa được test trên secure storage thiết bị thật.
4. Recovery Web chủ động từ chối PKCE code từ client khác; production phụ thuộc
   token-hash template được Auth fetch thành công.

### Phát hành

1. Đã có Apache-2.0 nhưng chưa audit license/provenance asset; release credential,
   notarization, installer và store metadata chưa hoàn chỉnh.
2. iOS cần xác minh trên simulator/thiết bị; Windows và Linux cần xác minh ngoài CI.
3. Chưa có integration test Flutter cho local storage, auth UI, lock, sync interruption và recovery; remote RLS contract test đã có.
4. Một số plugin Android vẫn dùng Kotlin Gradle Plugin legacy và phát cảnh báo tương thích tương lai từ Flutter; build hiện tại vẫn pass.

## CI và automation

- `.github/workflows/ci.yml` pin Flutter 3.44.6 và build Android, iOS simulator, macOS, Web, Windows, Linux.
- Quality job chạy documentation gate, generated-code drift, format, analyze và test.
- `.github/dependabot.yml` kiểm tra dependency Pub và GitHub Actions hằng tuần.

## Cập nhật tài liệu này

Chỉ đổi trạng thái khi có command hoặc test làm bằng chứng. Nếu một platform chưa được chạy trên host/device tương ứng, ghi **chưa xác minh** thay vì suy luận từ việc runner tồn tại.
