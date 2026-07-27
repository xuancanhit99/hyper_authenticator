# ADR-0016: Biên export Google Authenticator

- Trạng thái: Chấp nhận
- Ngày: 2026-07-27
- Owner: HyperZ
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

Người dùng cần chuyển nhiều TOTP account từ Hyper Authenticator sang Google
Authenticator. Mỗi QR transfer chứa raw TOTP secret; app lock đã mở trước đó
không phải fresh authorization cho hành động disclosure này. Reconstructed
Google migration schema version 1 cũng không biểu diễn custom period hoặc mã 7
chữ số.

Primary UI trước đây đã xóa action xuất một `otpauth` QR vì luồng đó không
reauthenticate, không cảnh báo và không có timeout. Đưa lại export mà chỉ bọc UI
quanh cùng URI sẽ tái tạo rủi ro cũ.

## Quyết định

1. Export dùng reconstructed Google Authenticator `MigrationPayload` version 1,
   cùng field contract với parser ADR-0015. Encoder bounded tối đa 100 account,
   100 part, text 2 KiB, secret 1 KiB và URI 1.800 ký tự.
2. Chỉ export TOTP có period 30 giây, SHA1/SHA256/SHA512 và 6/8 digits. Field
   không biểu diễn được fail closed; không tự thay default.
3. Batch có random positive `int32` ID. Encoder chia tuần tự thành nhiều QR và
   giữ thứ tự account; mỗi part có cùng version/size/ID và index riêng.
4. Người dùng phải chọn rõ account và fresh-authenticate qua OS ngay trước khi
   encoder tạo QR. Trạng thái app-lock thành công không được tái sử dụng. Nếu
   native auth trả success khi Flutter lifecycle chưa `resumed`, page chỉ chờ tối
   đa 2 giây; timeout fail closed và không tạo QR khi resume muộn.
5. QR chỉ sống trong widget memory 60 giây, tự xóa khi hết hạn, đóng thủ công
   hoặc app rời foreground. UI cảnh báo QR là credential và loại full URI/secret
   khỏi semantics/diagnostics.
6. Export fail closed trên Web/Linux vì capability matrix hiện chưa có OS
   reauthentication boundary. Android/iOS/macOS/Windows dùng `local_auth`, cho
   phép device credential fallback, đặt sensitive transaction và không persist
   authentication qua background.
7. Export không gọi repository, không mutate local vault và không gọi
   Supabase/sync.

## Phương án đã cân nhắc

### Dùng trạng thái `LocalAuthBloc`

Không chọn. State này có thể đã success từ lúc mở app, có thể bypass khi user
không bật app lock và ở platform unsupported còn chủ động phát success. Nó không
chứng minh fresh consent cho secret disclosure.

### Export từng account bằng `otpauth://totp`

Đơn giản và giữ custom period, nhưng không tương đương luồng Transfer accounts
của Google, khó chuyển nhiều account và từng bị gỡ vì thiếu security boundary.
Standard `otpauth` portability vẫn là task riêng.

### Cho export trên platform không có local auth

Không chọn. Một warning/confirmation trong app không thay thế OS authentication
và không đạt exit criteria của portability P0.

## Hệ quả

### Tích cực

- Multi-account/multi-part export có source contract round-trip với parser hiện có.
- Cancel/auth failure/encoding failure không ghi dữ liệu.
- Fresh auth, timeout và lifecycle cleanup thu hẹp thời gian credential hiện trên
  màn hình.

### Tiêu cực

- Linux/Web chưa export được.
- Account period khác 30 hoặc digits 7 phải chuyển bằng format khác trong tương lai.
- QR vẫn có thể bị camera ngoài hoặc active screen capture lấy trong cửa sổ 60 giây.

### Rủi ro

- Format Google thay đổi: Google Authenticator 7.2 trên Android AVD đã nhận
  encoder v1, nhưng physical interoperability vẫn là gate riêng và parser/encoder
  tiếp tục fail closed khi schema đổi.
- QR quá dày: giới hạn URI 1.800 ký tự với error correction M và chia batch; test
  QR thật vẫn cần thiết bị đại diện.
- OS auth plugin khác nhau theo platform: physical biometric/PIN/Windows Hello
  evidence vẫn nằm trong release gate.

## Bảo mật và quyền riêng tư

Object part override `toString` bằng `[REDACTED]`. UI không copy, share, persist,
log hoặc đưa URI vào BLoC/event. QR có semantics label mô tả part nhưng không
chứa data. Privacy Shield che app khi lifecycle rời foreground; control này không
phải active screenshot prevention.

## Dữ liệu và compatibility

Không đổi `AuthenticatorAccount`, local vault v2, encrypted snapshot, Supabase
schema/RPC hoặc production data. Export chỉ đọc snapshot `AccountsLoaded`.
Rollback code không cần data migration.

## Xác minh

- Encoder → parser/collector round-trip cho SHA1/SHA256 và 6/8 digits.
- Multi-part out-of-order, URI bounded, invalid period/digits fail closed.
- Fresh auth options, user cancel và unavailable device fail closed.
- Widget: chưa auth không có QR, success + lifecycle resumed mới render, bounded
  resume timeout, semantics redaction, background cleanup và unsupported
  platform.
- `scripts/agent/check.sh full` cùng Android/Web build smoke.

## Rollout

1. Mở action từ account list trên source-supported platform.
2. Hyper → Google Authenticator 7.2 đã pass trên Android AVD mà không lưu raw
   payload; tiếp tục physical Android/iOS đại diện.
3. Nếu Google không nhận fixture, giữ feature khỏi stable release và sửa encoder
   bằng fixture `TEST_ONLY`; không nới parser để đoán.
4. Revert route/UI/encoder nếu cần; vault và cloud data không đổi.
