# ADR-0015: Biên import Google Authenticator migration QR

- Trạng thái: Chấp nhận
- Ngày: 2026-07-25
- Owner: HyperZ
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

Google Authenticator có luồng Transfer accounts và có thể tạo nhiều QR cho một
export. Google xác nhận hành vi này nhưng không công bố schema của
`otpauth-migration://offline?data=...`. Format thực tế được cộng đồng tái dựng là
Base64 của protobuf `MigrationPayload`.

QR chứa raw TOTP secret. Luồng cũ của Hyper Authenticator chỉ parse một
`otpauth://totp` rồi persist ngay, không đủ cho multi-part, preview, duplicate
detection hoặc all-or-nothing import.

Runtime với Google Authenticator 7.2 trên Android AVD cho thấy app hiện phát
`MigrationPayload` version 2 và thêm một opaque identifier ở OTP field 8. Raw
payload/identifier không được đưa vào fixture hoặc evidence; test chỉ tái dựng
wire shape và độ dài đã quan sát.

## Quyết định

1. Hỗ trợ migration version 1 và wire shape version 2 đã quan sát qua một Dart
   parser bounded. V2 chỉ nhận đúng một OTP field 8 length-delimited,
   bounded/non-empty rồi bỏ khỏi domain. Unknown top-level/account field đều fail
   closed; không đoán ý nghĩa metadata.
2. Chỉ nhận TOTP, SHA1/SHA256/SHA512 và 6/8 digits. HOTP, MD5, version/enum/wire
   type lạ, payload quá giới hạn hoặc version/batch size không hợp lệ đều fail
   closed.
3. Multi-part collector chỉ sống trong memory, bind chính xác version,
   `batch_id`, `batch_size`, `batch_index`, nhận out-of-order và giới hạn tổng
   100 account. Scalar `batch_index`/`batch_id` vắng mặt dùng default proto3;
   `batch_id` giữ đúng signed `int32`.
4. Chỉ preview issuer/account name và tham số không phải secret. Cancel hoặc chưa
   đủ batch không gọi repository.
5. Sau xác nhận, use case validate toàn bộ batch rồi data source append account
   mới bằng đúng một local-vault COW commit. Exact duplicate được bỏ qua và chỉ
   trả count không nhạy cảm.
6. Schema Google không có period; TOTP import dùng 30 giây. Khi issuer trống và
   label không có prefix, UI dùng nhãn rõ `Không xác định`.

## Phương án đã cân nhắc

### Dùng generated protobuf từ schema tái dựng

Giảm code wire parser nhưng biến schema không chính thức thành dependency
generated rộng hơn cần thiết. Bounded decoder nhỏ giúp kiểm soát size, enum,
wire type và không cần cam kết mọi field là API ổn định.

### Persist từng account ngay khi scan

Đơn giản hơn nhưng tạo partial import khi batch sau lỗi/cancel và không cho người
dùng review toàn bộ credential destination. Không chọn.

### Dùng `replaceAccounts`

Có atomic primitive sẵn nhưng có thể xóa account local không thuộc export.
Import phải append/dedupe; destructive replace chỉ dành cho recovery đã review.

## Hệ quả

### Tích cực

- Import nhiều account không cần tài khoản/cloud và không ghi partial batch.
- Parser có giới hạn URI/payload/text/secret/account/batch rõ ràng.
- Không đổi persisted account hoặc vault format.

### Tiêu cực

- Format nguồn không phải API Google chính thức và có thể đổi.
- HOTP chưa import được.
- Custom period không round-trip vì migration schema không mang field này.

### Rủi ro

- Google đổi schema: version/enum lạ bị từ chối thay vì import sai; cần fixture và
  app-to-app evidence mới trước khi mở rộng. Android AVD v7.2 đã pass; physical
  Android/iOS vẫn là gate riêng.
- QR từ export khác bị trộn: collector từ chối và giữ batch đang quét.
- Account lặp: fingerprint canonical trong critical section loại exact duplicate.

## Bảo mật và quyền riêng tư

Payload, raw secret và full URI không được log, analytics, success state hoặc
semantics. Preview chỉ hiển thị issuer/account name và thuật toán. Event/DTO
override `toString` bằng `[REDACTED]`. Parser giới hạn input trước và sau Base64
decode để giảm memory abuse. QR export vẫn phải được xem như credential và người
dùng cần xóa ảnh/chia sẻ không an toàn sau import.

## Dữ liệu và compatibility

Không đổi `AuthenticatorAccount`, local-vault v2, encrypted envelope hoặc
Supabase schema/RPC. Account import nhận UUID mới; account hiện có giữ nguyên ID
và thứ tự. Rollback app không cần data migration.

## Xác minh

- Wire fixture `TEST_ONLY` cho version 1/2, algorithm/digits/label, v2 field 8
  bounded và unknown metadata fail-closed.
- Multi-part out-of-order, duplicate part, mixed batch, proto3 default/signed
  batch ID, account limit và HOTP fail-closed.
- Preview confirm/cancel, no-secret rendering, default focus Hủy và text scale
  200%.
- Atomic append/dedupe và commit-failure rollback.
- `scripts/agent/check.sh full` cùng Android/Web build smoke.

## Rollout

1. Phát hành import trong Add account scanner hiện có.
2. Google Authenticator 7.2 trên Android AVD đã pass app-to-app mà không giữ raw
   payload; tiếp tục xác minh trên physical Android/iOS đại diện.
3. Nếu schema thay đổi, thêm version support bằng fixture mới; không nới parser
   hiện tại để đoán.
4. Revert client nếu có lỗi; persisted format không đổi.
