# Hướng dẫn deployment và phát hành

Repository hiện chưa sẵn sàng phát hành. Tài liệu này định nghĩa gate, không xác nhận gate đã pass.

## Release environment

Duy trì Supabase project riêng cho development, test, staging và production. Mỗi environment cần:

- client configuration riêng;
- redirect URL rõ ràng;
- schema và RLS migration có version;
- user và dữ liệu test tổng hợp, độc lập;
- owner và rollback plan được ghi lại.

Không bao giờ phân phối service-role key.

## Release gate toàn cục

- Mọi blocker trong `PROJECT_STATUS.md` và `SECURITY.md` đã xử lý hoặc được chấp nhận rõ.
- Tên sản phẩm, bundle ID, application ID, URL, icon và store metadata nhất quán.
- Đã thêm file `LICENSE` rõ ràng.
- Privacy policy đã review theo hành vi thật.
- Không có TOTP secret production dạng plaintext trong Supabase.
- Sync atomic và có thể recovery.
- Logout không âm thầm xóa dữ liệu local.
- RLS migration và cross-user negative test pass.
- Analyzer không có error và không có warning chưa giải thích.
- Unit, widget và critical integration test pass.
- Dependency scan và secret scan pass.
- Đã diễn tập upgrade và rollback.
- Release artifact được ký bằng production credential.

## Versioning

Flutter version được định nghĩa trong `pubspec.yaml`:

    version: major.minor.patch+build

Trước release:

1. cập nhật version;
2. cập nhật release note;
3. xác nhận compatibility của schema và encrypted format;
4. tag đúng commit đã test;
5. lưu checksum và build provenance.

## Client configuration

Build hiện tại cần asset `.env` ở root với `SUPABASE_URL` và `SUPABASE_ANON_KEY`.

Trước khi chuẩn hóa deployment, cần chấp nhận ADR cho configuration injection. Yêu cầu:

- deterministic theo environment;
- artifact không chứa server secret;
- không sửa thủ công sau build;
- có thể nhận biết environment trong diagnostic không nhạy cảm;
- production build không thể vô tình trỏ vào development.

## Android

Build candidate:

    flutter build appbundle --release
    flutter build apk --release

Trước distribution:

- xóa fallback sang debug signing cho release;
- xác minh keystore và alias thực tế;
- kiểm tra merged release manifest;
- xác minh network, camera, biometric và backup behavior;
- quyết định code shrinking và keep rule;
- upload native debug symbol nếu cần;
- test install, upgrade, sign-in, TOTP, lock, sync và recovery trên API level đại diện;
- hoàn tất Play data-safety declaration theo hành vi thật.

## iOS

Build candidate:

    flutter build ipa --release

Trước distribution:

- xác minh bundle ID, team, signing và provisioning;
- xác minh usage description camera và Face ID;
- cấu hình, test universal link hoặc custom scheme cho password recovery;
- test Keychain qua reinstall, logout, backup và device restore;
- hoàn tất App Store privacy detail theo hành vi thật;
- validate trên thiết bị vật lý và TestFlight.

## macOS

Build candidate:

    flutter build macos --release

Trước distribution:

- cấu hình sandbox entitlement cho network client, camera, keychain và local-auth;
- sign và notarize;
- test hardened runtime artifact ngoài máy development;
- xác minh plugin registration và secure-storage behavior.

## Web

Build candidate:

    flutter build web --release

Trước distribution:

- xóa hoặc isolate platform import không được hỗ trợ;
- xác minh secure-storage semantic và ghi browser threat model;
- cấu hình SPA routing;
- đặt CSP, HSTS, referrer, permission và cache policy;
- pin, integrity-protect external script hoặc self-host;
- test auth redirect và recovery URL;
- không khẳng định mức bảo mật tương đương mobile khi chưa review.

## Windows và Linux

Runner tồn tại nhưng product support chưa được xác minh. Trước release:

- xác minh mọi plugin;
- định nghĩa installer, signing, update, secure storage, device lock và rollback;
- thêm platform integration test;
- cập nhật ma trận platform được hỗ trợ công khai.

## Trang web khôi phục mật khẩu

Trước khi deploy `reset-password-web`:

- triển khai cơ chế inject public client configuration;
- pin hoặc self-host Supabase JavaScript dependency;
- thêm CSP và security header khác;
- chỉ cho phép production recovery redirect;
- tắt cache recovery page và URL material nhạy cảm khi phù hợp;
- test session hết hạn, malformed, reuse và thành công;
- xóa verbose session logging;
- cung cấp link privacy và support.

## Backend rollout

Mọi backend change cần:

1. migration ID và review;
2. client compatibility tiến/lùi;
3. diễn tập staging;
4. RLS negative test;
5. backup hoặc rollback;
6. monitoring không log credential;
7. bằng chứng migration hoàn tất.

E2EE rollout phải theo `E2EE_DESIGN.md` và ADR được chấp nhận.

## Rollback

Rollback phải giữ snapshot local và remote hợp lệ gần nhất. Không rollback về client không đọc được encrypted/schema version hiện tại khi chưa có compatibility plan.

Ghi lại:

- client version bị ảnh hưởng;
- schema và format version;
- đường downgrade an toàn;
- bước restore dữ liệu;
- nội dung thông báo user;
- incident owner.

## Bằng chứng phát hành

Lưu cho mỗi release:

- commit và tag;
- phiên bản Flutter và Dart;
- dependency lockfile;
- xác minh generated code;
- kết quả analyzer và test;
- platform build log;
- schema migration version và kết quả RLS test;
- artifact hash;
- tham chiếu signing identity, không lưu private key material;
- privacy và store declaration đã duyệt.
