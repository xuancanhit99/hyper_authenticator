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
      --dart-define=SUPABASE_PUBLISHABLE_KEY=...

Hoặc dùng `--dart-define-from-file=<environment-file>` trong hệ thống build. File không được đóng gói như asset. Production pipeline phải bảo đảm:

- chỉ chứa public client configuration;
- environment deterministic và không sửa artifact sau build;
- production không thể trỏ nhầm development;
- log không in giá trị key/URL nhạy cảm theo chính sách tổ chức.

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

- triển khai inject public configuration;
- pin/self-host Supabase JavaScript dependency;
- thêm CSP và security headers;
- whitelist production redirect;
- kiểm soát cache/URL material;
- test expired, malformed, reused và successful session;
- không log session và thêm privacy/support link.

## Backend rollout và rollback

Mỗi backend change cần migration ID, compatibility tiến/lùi, staging rehearsal, RLS test, backup/rollback và monitoring đã redact. E2EE rollout theo `E2EE_DESIGN.md` cùng ADR được chấp nhận.

Rollback phải giữ snapshot hợp lệ gần nhất và không hạ client về phiên bản không đọc được schema/encrypted format hiện hành.

## Bằng chứng phát hành

Lưu commit/tag, Flutter/Dart version, `pubspec.lock`, generated-code check, analyzer/test/build log, migration/RLS result, artifact hash, signing identity reference và privacy/store declaration. Không lưu private key material trong repository.
