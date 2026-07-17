# Chiến lược kiểm thử

## Baseline hiện tại

Ngày 17 tháng 7 năm 2026:

- `flutter analyze`: pass, không có diagnostic.
- `flutter test`: 10 test pass.
- Format gate: pass.
- CI đa nền tảng đã được track.
- Chưa có widget test, BLoC test hoặc `integration_test` đầy đủ.

Test hiện có:

| Nhóm | Coverage |
|---|---|
| `AuthenticatorAccount` | JSON round-trip và default tương thích record cũ |
| `TotpUriParser` | URI đầy đủ, suy luận issuer và input không hợp lệ |
| `TotpValidator` | Chuẩn hóa Base32 và từ chối secret/algorithm/digits/period không hợp lệ |
| `GenerateTotpCode` | RFC 6238 SHA1 known-answer vector tại mốc 59 giây |
| `AuthBloc` | Sign-in emit authenticated và sign-up chờ email không mắc kẹt ở loading |

## Quality gate

    scripts/agent/check.sh docs
    scripts/agent/check.sh quick
    scripts/agent/check.sh full

- `docs`: kiểm tra link, cấu trúc và drift tài liệu.
- `quick`: generated-code drift, format và analyze.
- `full`: toàn bộ quick gate cùng `flutter test`.

Build verification độc lập:

    scripts/agent/build.sh host
    scripts/agent/build.sh <android|ios|macos|web|windows|linux>

Không biến lỗi baseline thành success giả. Platform không build được trên host phải được ghi là chưa xác minh và chuyển sang runner phù hợp.

## Các tầng test cần bổ sung

### Unit test

- RFC 6238 SHA1/SHA256/SHA512, digits và period khác nhau.
- Base32 normalization và validation boundary.
- Local storage CRUD, index corruption và partial write recovery.
- Failure mapping ở repository.
- Merge identity, conflict, deletion và encrypted envelope sau khi có E2EE.

### BLoC test

- `AuthBloc`: sign-in/up/recovery/sign-out và giữ dữ liệu local khi logout.
- `AccountsBloc`: load/add/update/delete/merge và partial failure.
- `LocalAuthBloc`: lifecycle, cancel, unsupported platform và fail-closed error.
- `SyncBloc`: disabled, merge, overwrite, network failure, conflict và retry.
- `SettingsBloc`: persistence của preference.

### Widget test

- Validation auth và manual TOTP.
- Parse QR, hiển thị lỗi không lộ secret và capability theo platform.
- Countdown/copy code, delete confirmation và lock-screen retry.
- Theme và sync settings.

Plugin boundary cần wrapper hoặc fake để test không phụ thuộc camera/keychain/sinh trắc học thật.

### Integration test

1. Đăng nhập và load dữ liệu local.
2. Thêm SHA1/SHA256/SHA512, 6–8 digits và period tùy chỉnh rồi restart.
3. Background/resume và unlock.
4. Logout không làm mất TOTP local.
5. Interrupted upload không làm mất snapshot hợp lệ gần nhất.
6. Merge/concurrency hai thiết bị.
7. User A không truy cập row của User B qua RLS.
8. Recovery link thành công, hết hạn, malformed và reuse.

Dùng Supabase environment isolated và dữ liệu tổng hợp.

## Xác minh platform

Với mỗi platform được quảng bá:

- clean install và upgrade;
- secure-storage persistence/deletion;
- local authentication và cancel nếu có hỗ trợ;
- camera/gallery permission nếu có hỗ trợ;
- network trong release build;
- lifecycle và deep link;
- signing, entitlement/sandbox và installer;
- accessibility cơ bản.

## CI hiện tại

`.github/workflows/ci.yml` gồm:

- quality gate trên Ubuntu;
- Android debug APK;
- Web release;
- Linux release;
- Windows release;
- macOS debug;
- iOS simulator debug không codesign.

CI pin Flutter 3.44.6 và Java 17 cho Android. Không đưa production credential vào CI; build không cần Supabase define, còn integration test tương lai chỉ nhận public client config của environment test.

## Fixture và báo lỗi

- Dùng email/domain `.invalid` và RFC vector tổng hợp.
- Đánh dấu fixture trông giống secret là `TEST_ONLY`.
- Không snapshot Supabase session/response thật.
- Redact URI `otpauth`, secret, token và password khỏi output.

## Definition of done

Thay đổi hành vi hoàn tất khi có acceptance criteria quan sát được, regression test theo rủi ro, quality gate pass, failure behavior được kiểm tra và tài liệu canonical liên quan đã cập nhật. Thay đổi platform cần kèm bằng chứng build/test trên runner hoặc thiết bị phù hợp.
