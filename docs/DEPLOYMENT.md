# Hướng dẫn deployment và phát hành

Repository build được trên nhiều platform nhưng chưa production-ready. Tài liệu này định nghĩa release gate, không xác nhận gate đã pass.

## Release environment

Duy trì Supabase project riêng cho development, test, staging và production. Mỗi environment cần public client configuration, redirect URL, migration/RLS version, dữ liệu test tổng hợp, owner và rollback plan. Không phân phối service-role key.

## Gate toàn cục

- Blocker trong `PROJECT_STATUS.md` và `SECURITY.md` đã xử lý hoặc được owner chấp nhận rõ.
- Tên, identifier, icon, URL và store metadata nhất quán.
- Có `LICENSE` và privacy policy.
- Không có plaintext TOTP secret trong cloud.
- Sync atomic/idempotent, có conflict và recovery protocol.
- RLS migration cùng cross-user negative test pass.
- Format, analyze, test, generated-code, docs, dependency và secret scan pass.
- Release artifact được ký bằng production credential và có rollback/upgrade evidence.

## Versioning

`pubspec.yaml` dùng:

    version: major.minor.patch+build

Trước release: cập nhật version/release note, xác nhận schema/encrypted-format compatibility, tag đúng commit đã test và lưu artifact checksum/provenance.

## Client configuration

Configuration được inject lúc compile:

    flutter build <target> \
      --dart-define=SUPABASE_URL=... \
      --dart-define=SUPABASE_PUBLISHABLE_KEY=... \
      --dart-define=PASSWORD_RECOVERY_URL=https://auth.example.com/reset-password/

Hoặc dùng `--dart-define-from-file=<environment-file>` trong hệ thống build. File không được đóng gói như asset. Production pipeline phải bảo đảm:

- chỉ chứa public client configuration;
- environment deterministic và không sửa artifact sau build;
- production không thể trỏ nhầm development;
- log không in giá trị key/URL nhạy cảm theo chính sách tổ chức.
- `ALLOW_INSECURE_PLAINTEXT_SYNC=false`; release binary vẫn fail closed nếu define
  này bị bật nhầm.

## Android

    flutter build appbundle --release \
      --dart-define-from-file=.env.production

Trước distribution:

- cấu hình release keystore; không dùng debug-signing fallback;
- kiểm tra merged manifest, network, camera, biometric và `allowBackup=false`;
- quyết định shrinking/keep rule và native symbols;
- test install/upgrade, auth, TOTP, lock, sync/recovery trên API đại diện;
- hoàn tất Play data-safety theo behavior thật.

## iOS

    flutter build ipa --release \
      --dart-define-from-file=.env.production

Trước distribution:

- xác minh SwiftPM resolution, bundle ID, team, signing/provisioning;
- test camera/photo/Face ID usage, Keychain access group và reinstall/restore;
- cấu hình universal/custom link cho recovery;
- validate trên thiết bị vật lý và TestFlight;
- hoàn tất App Store privacy detail.

Project không còn CocoaPods integration; `pubspec.lock` là dependency lock chính, còn SwiftPM plugin graph được Flutter generate từ plugin metadata.

## macOS

    flutter build macos --release \
      --dart-define-from-file=.env.production

Trước distribution:

- xác minh SwiftPM resolution;
- xác minh sandbox network/camera, Keychain access group và local-auth entitlement;
- sign, hardened runtime và notarize;
- test artifact ngoài máy development cùng secure-storage behavior.

## Web

    flutter build web --release \
      --dart-define-from-file=.env.production

Trước distribution:

- ghi threat model cho browser storage/session;
- cấu hình SPA routing, CSP, HSTS, referrer/permission/cache policy;
- pin/self-host external script khi cần;
- test auth/recovery redirect;
- không quảng bá mức bảo mật tương đương mobile nếu chưa có review.

## Windows

    flutter build windows --release \
      --dart-define-from-file=.env.production

Xác minh secure storage, Windows Hello/device auth, manual TOTP flow, installer/signing, upgrade và rollback. Scanner camera hiện không thuộc capability của app trên Windows.

## Linux

    flutter build linux --release \
      --dart-define-from-file=.env.production

Xác minh secure storage backend/keyring, package/installer/signing, desktop integration và manual TOTP flow. Scanner/local-auth hiện bị tắt trên Linux.

## Trang recovery tĩnh

Trước khi deploy `reset-password-web`:

- [x] inject public configuration lúc container start và từ chối secret/service key;
- [x] pin Supabase JavaScript dependency bằng version cùng SRI;
- [x] thêm CSP, HSTS và security headers;
- [x] whitelist exact production `PASSWORD_RECOVERY_URL`;
- [x] no-store, xóa recovery material khỏi URL và không log access/session;
- [ ] remote contract đã pass successful/malformed/reused; còn expired token và
  email-provider delivery E2E;
- [x] cấu hình `GOTRUE_MAILER_TEMPLATES_RECOVERY` trỏ file template đóng gói;
- [x] remote token contract xác minh fragment `token_hash`/`verifyOtp`, update,
  re-login và chống reuse; email body/provider thật vẫn cần smoke test;
- thêm privacy/support link phù hợp deployment production.

`reset-password-web/test.sh` là gate local cho image/config/header;
`test-remote.sh` kiểm tra public HTTPS deployment. Trang chủ động từ chối `?code`
PKCE từ Flutter vì không có verifier. Không coi recovery release gate hoàn tất
trước khi SMTP mailbox và expired-token E2E pass.

## E2EE sync v2 staged rollout

1. Chạy `scripts/supabase/test_encrypted_vault_migration.sh` local/CI.
2. Backup và rehearsal staging rồi áp migration additive
   `20260718190000_create_encrypted_vault_snapshots.sql`.
3. Chạy catalog/RLS/RPC conflict test bằng isolated users.
4. Chỉ enable client sau khi onboarding bắt user export recovery key và import
   rehearsal pass trên thiết bị thứ hai.
5. Giữ `synced_accounts` compatibility; không drop plaintext trong rollout này.
   Drop cần migration/backup/rollback riêng.

## Supabase self-hosted

### Baseline đã triển khai

Backend hiện dùng Docker release `self-hosted/v0.7.0`, commit và PostgreSQL image
được pin trong `supabase/UPSTREAM_PIN`. Không deploy trực tiếp nhánh upstream
`master` vì có thể chứa thay đổi `Unreleased`.

Core bundle gồm PostgreSQL, Studio, Kong, Auth, PostgREST, Realtime, Storage,
imgproxy, postgres-meta, Edge Runtime và Supavisor. Logs/Analytics là optional và
chưa bật do host chỉ có khoảng 7,8 GB RAM và chưa có load-test headroom. Disk
cleanup ngày 17 tháng 7 năm 2026 đưa mức dùng từ 93% xuống 67%, còn khoảng 24 GB;
Vault MTLS POC sau đó đã được owner yêu cầu xóa, giúp swap giảm còn khoảng 1,2/2 GB.

Trên cùng host, Keycloak VNPAY được giới hạn ở 3 GiB RAM (`mem_limit`) với 1 GiB
reservation. JVM của nó dùng heap khởi tạo 25% và heap tối đa 65% của container,
thay vì mặc định tính theo toàn bộ RAM host. Không bật Logs/Analytics hoặc service
mới trước khi đo cold-start và tải ổn định lại. Compose của Keycloak hiện chạy
`start-dev`; sau cold start ngày 17 tháng 7 năm 2026, healthcheck trên cổng 9000
đã `healthy` và OIDC discovery qua cổng HTTP đã trả `200`. Vẫn cần load test trước
khi coi 3 GiB là ngưỡng production ổn định.

Public boundary:

- reverse proxy hiện có terminate TLS;
- Kong tham gia external network `proxy-network` để proxy resolve bằng container
  name, tránh phụ thuộc container IP;
- Kong HTTP/HTTPS và Supavisor session/transaction port chỉ bind `127.0.0.1`;
- PostgreSQL/Studio/service nội bộ không publish trực tiếp ra Internet.

Overlay tái lập nằm trong `supabase/docker-compose.public-proxy.yml`. Mất external
network attachment sẽ làm public endpoint trả `502` dù container vẫn healthy, nên
health check phải gồm cả loopback và public TLS path.

Host maintenance baseline:

- SSH `LogLevel INFO`; DEBUG3 trước đây làm `auth.log` tăng hơn 3 GB khi bị scan;
- journald giới hạn `SystemMaxUse=1G`, giữ tối đa 14 ngày và chừa 10 GB filesystem;
- rsyslog vẫn rotate/compress log; không truncate active log;
- Docker chỉ prune build cache không còn tham chiếu; không prune volume hoặc image
  đang được container dùng;
- SSH chỉ chấp nhận public key; password và keyboard-interactive authentication đã
  tắt, fresh key connection pass và password-only connection bị từ chối;
- Fail2ban và UFW chưa được cấu hình, vẫn là defense-in-depth follow-up.

### Rollout backend

1. Pin release/commit official và review changelog/compose diff.
2. Backup database globals/full dump, Storage files và config; checksum và rehearsal
   trước thao tác phá hủy.
3. Sinh mới database password, JWT/key, dashboard credential, encryption key và
   pooler tenant. Không tái sử dụng secret legacy.
4. Xác minh SMTP, Site URL và redirect allow-list mà không log giá trị.
5. Start core stack, chờ mọi health check pass rồi nối reverse proxy.
6. Áp dụng migration theo thứ tự trong `supabase/migrations`.
7. Chạy smoke test official, auth-key/JWKS test và
   `scripts/supabase/test_remote_contract.sh` qua public HTTPS endpoint.
8. Dọn test user/row/bucket/audit và xác minh application data count bằng 0.
9. Cập nhật Flutter public URL/publishable key, build/test từ cùng source contract.

Hướng dẫn upstream cần đối chiếu mỗi lần nâng:

- [Self-hosting with Docker](https://supabase.com/docs/guides/self-hosting/docker)
- [Self-hosted Auth API keys](https://supabase.com/docs/guides/self-hosting/self-hosted-auth-keys)
- [PostgreSQL 17 upgrade](https://supabase.com/docs/guides/self-hosting/postgres-upgrade-17)

### Backup và rollback

Runbook cùng artifact legacy nằm trong
[`operations/SUPABASE_LEGACY_BACKUP.md`](operations/SUPABASE_LEGACY_BACKUP.md).
Backup hiện tại là manual point-in-time; trước production cần encrypted off-host
copy, retention, alert và scheduled restore rehearsal.

Rollback không được import full dump legacy vào instance mới đang chạy. Dựng một
stack cô lập khớp version legacy, restore và kiểm tra ở đó; hoặc rollback clean
deployment bằng backup cùng version. Client camelCase cũ không tương thích schema
snake_case mới.

## Backend rollout và rollback

Mỗi backend change cần migration ID, compatibility tiến/lùi, staging rehearsal, RLS test, backup/rollback và monitoring đã redact. E2EE rollout theo `E2EE_DESIGN.md` cùng ADR được chấp nhận.

Rollback phải giữ snapshot hợp lệ gần nhất và không hạ client về phiên bản không đọc được schema/encrypted format hiện hành.

## Bằng chứng phát hành

Lưu commit/tag, Flutter/Dart version, `pubspec.lock`, generated-code check, analyzer/test/build log, migration/RLS result, artifact hash, signing identity reference và privacy/store declaration. Không lưu private key material trong repository.
