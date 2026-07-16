# Chiến lược kiểm thử

## Baseline hiện tại

Automated product test chưa được triển khai.

- `test/widget_test.dart` đã bị comment toàn bộ.
- Không có thư mục `integration_test`.
- Native test target chỉ có template.
- Không có CI pipeline được track.
- `flutter test` hiện dừng khi thiếu `.env` vì file này được khai báo là asset.
- Static analysis baseline ngày 17 tháng 7 năm 2026: 0 error, 29 warning, 72 info diagnostic.

Phần này phải được giữ cho đến khi test và CI thay thế baseline.

## Quality gate

Tài liệu:

    scripts/agent/check.sh docs

Gate Dart và Flutter nhanh:

    scripts/agent/check.sh quick

Gate đầy đủ:

    scripts/agent/check.sh full

Harness được thiết kế nghiêm ngặt. Baseline failure đã biết phải được báo, không che giấu. Khi một check bị chặn, vẫn chạy mọi check không bị ảnh hưởng.

## Các tầng test

### Unit test

Ưu tiên cao nhất:

- Known-answer TOTP theo RFC 6238 và package.
- Validation algorithm, digits và period.
- JSON round trip của `AuthenticatorAccount`.
- Create/read/update/delete local storage và index recovery.
- Ánh xạ exception thành failure ở repository.
- Merge identity và conflict behavior.
- Encrypted envelope và migration sau khi có E2EE.

### BLoC test

Dùng `bloc_test` hoặc package tương đương sau khi thêm vào `dev_dependencies`.

Cần bao phủ:

- `AuthBloc`: sign-in, sign-up, recovery, sign-out và quyền sở hữu dữ liệu an toàn.
- `AccountsBloc`: load, add, update, delete, merge và partial failure.
- `LocalAuthBloc`: lifecycle, cancel, thiết bị không hỗ trợ và error fail-closed.
- `SyncBloc`: disabled, merge, overwrite, network failure, concurrency conflict và retry.
- `SettingsBloc`: persistence của preference.

### Widget test

Cần bao phủ:

- validation đăng nhập và đăng ký;
- phản hồi khi nhập thủ công hoặc parse QR;
- format mã trong danh sách và hành vi copy;
- cảnh báo delete và logout phá hủy dữ liệu;
- retry và error trên lock screen;
- mô tả tùy chọn sync và disabled state;
- đổi theme.

Mọi plugin boundary phải có thể thay bằng fake.

### Integration test

User journey quan trọng:

1. Đăng nhập và load tài khoản local có sẵn.
2. Thêm tài khoản TOTP chuẩn và xác minh known code.
3. Thêm SHA256, 8 digits, period khác 30 giây và xác minh round trip.
4. Background, resume và unlock ứng dụng đã cấu hình khóa.
5. Logout không làm mất dữ liệu local ngoài ý muốn.
6. Download và merge không ghi đè conflict.
7. Upload bị gián đoạn không làm mất cloud snapshot hợp lệ gần nhất.
8. User A không truy cập dữ liệu User B qua Supabase RLS.
9. Link password recovery thành công, hết hạn và reuse.

Dùng môi trường isolated với dữ liệu tổng hợp; không dùng production credential.

### Xác minh platform

Với mỗi platform được hỗ trợ:

- clean install và upgrade;
- persistence và deletion semantic của secure storage;
- khả dụng và cancel sinh trắc học/credential thiết bị;
- permission camera và gallery;
- network trong release build;
- background và resume;
- deep link;
- release signing và sandbox entitlement.

## Fixture

- Dùng địa chỉ `example.invalid`.
- Dùng RFC test vector tổng hợp, không dùng account cá nhân.
- Đánh dấu mọi fixture trông giống secret là `TEST_ONLY`.
- Không snapshot Supabase response hoặc session thật.
- Redact secret trong URI `otpauth` khỏi failure output.

## Coverage policy

Tỷ lệ coverage đứng sau coverage theo rủi ro. Tuy nhiên trước beta:

- mọi domain use case có test success và failure;
- mọi persisted model có round-trip test và migration test;
- mọi destructive path có interruption và rollback test;
- auth, lock, sync và recovery có integration coverage;
- security regression có permanent test.

Không loại file security-critical chỉ để tăng phần trăm coverage.

## Mục tiêu CI

Pull-request pipeline trong tương lai nên chạy:

1. resolve dependency bằng Flutter version được pin;
2. generated-code drift check;
3. formatting check;
4. static analysis không có diagnostic mới;
5. unit test và widget test;
6. documentation harness;
7. secret scanning;
8. ít nhất Android debug build;
9. suite integration Supabase và platform theo lịch hoặc protected branch.

CI chỉ được nhận public client configuration theo environment. Không cho phép production credential.

## Definition of done

Thay đổi hành vi chỉ hoàn tất khi:

- acceptance criteria có thể quan sát;
- có regression coverage;
- quality gate liên quan pass hoặc blocker có sẵn được báo chính xác;
- failure behavior về dữ liệu và bảo mật đã được test;
- tài liệu canonical bị ảnh hưởng đã cập nhật;
- xác minh đặc thù platform được ghi lại khi áp dụng.
