# ADR-0017: Biên portability chuẩn otpauth

- Trạng thái: Chấp nhận
- Ngày: 2026-07-27
- Owner: HyperZ
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

Key URI Format `otpauth://totp` là định dạng de facto được nhiều ứng dụng
authenticator dùng để trao đổi một TOTP account qua QR. Hyper Authenticator đã
parse định dạng này khi thêm account, nhưng trước đây scanner persist ngay sau khi
parse: người dùng không có preview/cancel và luồng không đi qua atomic import
boundary đã có cho Google Authenticator.

Google migration QR giải quyết tốt chuyển nhiều account nhưng không biểu diễn
custom period hoặc mã 7 chữ số. Standard `otpauth` cần được hỗ trợ như lựa chọn
portability riêng, đồng thời không khôi phục action cũ từng hiển thị credential mà
không fresh-authenticate hoặc giới hạn thời gian.

## Quyết định

1. Chỉ nhận scheme `otpauth`, type `totp`, đúng một path segment và không nhận
   user info, port hoặc fragment. URI import tối đa 16 KiB.
2. `secret`, `issuer`, `algorithm`, `digits` và `period` là security-relevant
   query parameter: mỗi field chỉ được xuất hiện tối đa một lần. Unknown parameter
   được bỏ qua để giữ interoperability; HOTP và dữ liệu TOTP ngoài allowlist fail
   closed.
3. Parser và exporter giữ nguyên issuer, account name, Base32 secret,
   SHA1/SHA256/SHA512, 6–8 digits và period dương. Label/query được encode sao cho
   issuer hoặc account name chứa dấu hai chấm vẫn round-trip chính xác.
4. Standard QR import luôn mở preview không chứa secret. Cancel không mutate;
   confirm dùng `ImportAccountsRequested`, validate toàn bộ, dedupe exact identity
   trong critical section và append bằng một local-vault COW commit.
5. Standard export tạo đúng một QR cho mỗi account, tối đa 100 account và 1.800
   ký tự mỗi URI. Toàn bộ account được validate trước khi trả list để không tạo
   partial export.
6. Standard và Google export dùng chung protected disclosure page: user chọn
   format/account, fresh-authenticate qua OS, QR chỉ nằm trong widget memory tối
   đa 60 giây và bị xóa khi app rời foreground hoặc user đóng.
7. URI/secret không được đưa vào BLoC, route, clipboard, file, Supabase,
   diagnostics hoặc semantics. Export tiếp tục fail closed trên Web/Linux vì chưa
   có OS reauthentication boundary.

## Phương án đã cân nhắc

### Persist standard QR ngay sau khi scan

Ít thao tác hơn nhưng không cho user xác nhận destination và tạo boundary khác
với Google import. Không chọn.

### Gộp nhiều account vào một standard QR

Key URI Format chỉ mô tả một credential. Tự tạo container mới sẽ không còn
interoperable. Không chọn; UI hiển thị tuần tự một QR cho mỗi account.

### Cho standard export không cần fresh OS auth

Không chọn. Full URI chứa raw TOTP secret và có cùng disclosure risk với Google
migration QR; warning trong app không thay thế fresh authorization.

### Từ chối mọi unknown query parameter

Fail closed tuyệt đối nhưng làm giảm khả năng nhập QR do implementation khác thêm
metadata không ảnh hưởng TOTP. Chỉ parameter được app dùng để tạo credential mới
bị khóa duplicate; unknown parameter được bỏ qua.

## Hệ quả

### Tích cực

- Chuyển được account có custom algorithm/digits/period giữa các app hỗ trợ
  standard.
- Standard và Google import/export có cùng preview, atomicity và protected
  disclosure boundary.
- Không đổi persisted account, local-vault, encrypted envelope hoặc backend.

### Tiêu cực

- N account cần quét N QR; standard format không có batch metadata.
- HOTP chưa được hỗ trợ.
- Compatibility thực tế vẫn phụ thuộc parser của app nhận, đặc biệt với custom
  algorithm/digits/period.

### Rủi ro

- QR đang hiển thị vẫn có thể bị camera ngoài hoặc active screen capture lấy;
  timeout và Privacy Shield không ngăn được trường hợp này.
- URI quá dày có thể khó quét; exporter giới hạn 1.800 ký tự và physical
  interoperability vẫn là gate riêng.
- Duplicate chỉ bỏ qua exact canonical identity; account gần giống nhưng khác
  secret hoặc tham số vẫn được xem là credential riêng.

## Bảo mật và quyền riêng tư

Export part override `toString` bằng `[REDACTED]`. Preview chỉ render issuer,
account name, algorithm, digits và period. Import parser failure, cancel và export
authentication failure không gọi mutation hoặc tạo QR. Account identity được
hiển thị để user review nhưng full URI/secret không vào semantics.

## Dữ liệu và compatibility

Không đổi `AuthenticatorAccount`, local vault v2, encrypted snapshot, Supabase
schema/RPC hoặc production data. Account import nhận UUID mới; exact duplicate
giữ account hiện có. Rollback code không cần data migration.

## Xác minh

- Exporter → parser round-trip cho dấu hai chấm, Unicode,
  SHA1/SHA256/SHA512, 6–8 digits và custom period.
- Duplicate security parameter, HOTP, invalid Base32, URI/account/QR limit fail
  closed và exporter không trả partial list.
- Preview confirm/cancel, no-secret rendering và atomic import path.
- Multi-account standard QR navigation, fresh auth, timeout/lifecycle cleanup,
  unsupported platform và viewport 320×640/text scale 200%.
- `scripts/agent/check.sh full`.

## Rollout

1. Phát hành standard import trong scanner hiện có và format selector trong
   protected export page.
2. Xác minh Hyper ↔ app authenticator khác trên physical Android/iOS đại diện mà
   không lưu raw payload/secret/OTP vào evidence.
3. Nếu app nhận không hỗ trợ custom semantics, giữ Google transfer như lựa chọn
   riêng; không âm thầm thay algorithm/digits/period.
4. Revert parser/exporter/UI nếu cần; vault và cloud data không cần downgrade.
