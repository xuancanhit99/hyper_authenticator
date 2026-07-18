# ADR-0009: Đóng băng Windows storage identity tương thích release lịch sử

- Trạng thái: Chấp nhận
- Ngày: 2026-07-18
- Owner: canhvx
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

`path_provider_windows` tạo application-support path từ `CompanyName` và
`ProductName` trong VERSIONINFO. Release lịch sử `1.0.0+9` dùng
`app.hyperz.authenticator\hyper_authenticator`; một đợt làm mới metadata đổi
`ProductName` thành `Hyper Authenticator`, khiến plugin nhìn sang sibling AppData.
Vault cũ vẫn còn nhưng app mới có thể hiển thị rỗng, tương đương sự cố mất khả
năng truy cập dữ liệu.

`flutter_secure_storage_windows 3.1.2` ghi mỗi logical key thành `*.secure` ở
application-support path. Bản hiện tại có backward-compatible reader và có thể
migrate chúng sang `flutter_secure_storage.dat`, nhưng chỉ khi physical path đúng.

## Quyết định

- Giữ `CompanyName=app.hyperz.authenticator` và
  `ProductName=hyper_authenticator` làm Windows storage identity canonical.
- Tên hiển thị tiếp tục là “Hyper Authenticator” qua window title,
  `FileDescription`, installer và shortcut; không dùng `ProductName` để làm đẹp.
- Trước DI/SharedPreferences/Supabase, startup migrator kiểm tra sibling
  `Hyper Authenticator` và chỉ nhập top-level `*.secure`,
  `flutter_secure_storage.dat`, `shared_preferences.json`.
- Copy dùng temporary file cùng thư mục rồi rename; verify byte, giữ nguyên nguồn,
  không theo symlink và ghi marker sau khi toàn bộ import thành công.
- Nếu source và target cùng có vault nhưng tập tên/byte khác nhau, app dừng với
  thông báo recovery an toàn; không merge, chọn newest hoặc overwrite tự động.
- CI pin source `1.0.0+9` và dependency lock lịch sử để chứng minh logical upgrade
  thật trên GitHub-hosted Windows. Build tạm chỉ thêm compile-definition mà MSVC
  14.51 yêu cầu cho `local_auth_windows 1.0.11`; không đổi storage code/metadata.
  Destructive harness không chạy trên workstation.

## Phương án đã cân nhắc

### Giữ ProductName thân thiện và chỉ copy thư mục cũ

Không chọn vì đổi storage identity của release đã tồn tại không cần thiết và tạo
thêm một migration bắt buộc cho mọi user lịch sử. Tên hiển thị đã có channel riêng.

### Merge hai vault theo timestamp

Không chọn vì timestamp/file set không đủ xác định snapshot nào authoritative;
merge TOTP credential âm thầm có thể phục hồi record đã xóa hoặc che corruption.

### Chỉ đổi metadata về lịch sử, bỏ migrator

Không chọn vì pre-release dùng tên thân thiện có thể đã ghi data thật. Giữ nguồn
và conflict fail-closed bảo toàn cả hai phía để recovery thủ công khi cần.

## Hệ quả

### Tích cực

- Upgrade từ `1.0.0+9` nhìn đúng legacy vault mà không cần copy physical path.
- Pre-release friendly path được nhập một lần, atomic và không phá nguồn.
- Metadata hiển thị cho người dùng vẫn chuyên nghiệp, độc lập storage identity.

### Tiêu cực

- `ProductName` kỹ thuật không được đổi nếu chưa có ADR/migration mới.
- Conflict yêu cầu backup AppData và hỗ trợ thủ công thay vì app tự khởi động.
- Startup Windows có thêm một I/O gate trước dependency injection.

### Rủi ro

- Crash/permission failure có thể để temporary file; lần sau không allowlist nên
  không được nhập. File đích đã tạo được rollback best-effort và marker không ghi.
- Marker ngăn import lặp lại; chạy lại một pre-release cũ sau migration có thể tạo
  data mới ở sibling mà current app không tự merge. Đây là downgrade không hỗ trợ.

## Bảo mật và quyền riêng tư

Migrator không decrypt, parse hoặc log secret/path. Nó chỉ copy file allowlist,
không theo link và không xóa source. Error UI/log chỉ có type/message cố định.
Historical harness dùng fixture công khai `TEST_ONLY`, profile hosted tạm và guard
explicit; không nhận service-role key hoặc vault người dùng.

## Dữ liệu và compatibility

Không đổi logical `AuthenticatorAccount` hoặc COW v2 format. Physical path
canonical là `%APPDATA%\app.hyperz.authenticator\hyper_authenticator`; marker
`.ha-storage-layout-v1-imported` không chứa credential. Rollback code được phép
tiếp tục đọc canonical path nhưng không được đổi lại ProductName hoặc xóa sibling
trước khi người dùng đã xác minh vault.

## Xác minh

- Unit test: no-op, allowlist atomic copy, source retention, idempotent marker,
  byte-level conflict, symlink rejection và rollback failure.
- Full quality gate: format/analyze/platform config/Flutter test.
- Hosted Windows: build source `1.0.0+9`, seed bằng plugin 3.1.2, current UI đọc
  đủ SHA256/8 digits/45 giây, COW v2 xuất hiện và cleanup pass.
- Installer transition tiếp tục xác minh uninstall không xóa canonical AppData.

## Rollout

1. Ship ProductName canonical và startup migrator trong cùng release.
2. Chạy full local gate và hosted historical-upgrade gate trước artifact build.
3. Không ký/phân phối nếu historical gate fail.
4. Khi conflict thực tế, dừng app, backup cả hai directory rồi dùng recovery tool
   có review riêng; không sửa trực tiếp trên bản production.
