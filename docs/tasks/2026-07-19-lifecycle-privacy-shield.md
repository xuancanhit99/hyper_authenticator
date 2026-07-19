# Task: Che nội dung nhạy cảm khi rời foreground

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-07-19
- Owner: canhvx
- Issue hoặc ADR liên quan: Không; control presentation không đổi kiến trúc hoặc data contract

## Mục tiêu

Che TOTP, recovery key và user identity khi ứng dụng chuyển khỏi `resumed`, không
làm mất state hoặc thay đổi local/cloud vault.

## Ngoài phạm vi

- Không tuyên bố chặn active screenshot, screen recording hoặc camera ngoài.
- Không bật native capture-blocking khi chưa chốt tác động tới screenshot/casting
  và chưa có runtime gate theo platform.

## Acceptance criteria

- [x] Toàn bộ router bị che ở `inactive`, `hidden`, `paused` và `detached`.
- [x] Nội dung bên dưới không nhận pointer, không giữ focus, không chạy ticker và
  không xuất hiện trong semantics tree khi shield đang bật.
- [x] `resumed` khôi phục UI hiện có mà không dispose hoặc mutate data.
- [x] Có regression test dùng placeholder, không chứa credential thật.
- [x] Full canonical gate pass.

## Bằng chứng hiện tại

- Source path: `lib/core/security/privacy_shield.dart`, `lib/app.dart`.
- Cách tái hiện: điều khiển `AppLifecycleState` trong widget test.
- Test hiện có: `test/core/security/privacy_shield_test.dart`.
- Giả định: Flutter dispatch lifecycle trước khi OS lấy background snapshot; giả
  định này vẫn cần native device/app-switcher screenshot test riêng.

## Đánh giá rủi ro

- Lộ credential: giảm rủi ro background snapshot; active capture vẫn là accepted risk.
- Mất dữ liệu local: không có write/dispose/reload vault.
- Mất dữ liệu cloud: không có network hoặc sync operation.
- Migration: không có persisted contract change.
- Rollback: bỏ `PrivacyShield` khỏi `MaterialApp.router.builder` và xóa widget/test.
- Tác động platform: cùng Flutter path trên sáu target; native capture API chưa bật.

## Audit active capture

- Android: [`FLAG_SECURE`](https://developer.android.com/security/fraud-prevention/activities)
  có thể chặn system screenshot/non-secure display, nhưng cần product decision và
  device runtime gate trước khi bật.
- iOS: notification screenshot được gửi
  [sau khi screenshot đã xảy ra](https://developer.apple.com/documentation/uikit/uiapplication/userdidtakescreenshotnotification);
  capture-status notification hỗ trợ phản ứng với recording/mirroring nhưng không
  phải bằng chứng chặn screenshot.
- Windows: [`WDA_EXCLUDEFROMCAPTURE`](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity)
  là best-effort qua DWM, không bảo vệ tuyệt đối.
- macOS: [`NSWindow.SharingType.none`](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum)
  là legacy constant không còn được macOS dùng.
- Linux/Web: chưa có portable control được project xác minh.

## Kế hoạch

- [x] Thêm root privacy shield fail closed.
- [x] Thêm lifecycle/focus/pointer/semantics regression.
- [x] Cập nhật security, system design, NFR, testing, roadmap và project status.
- [x] Chạy full gate và review diff.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `flutter test test/core/security/privacy_shield_test.dart test/app_localization_test.dart` | Pass 2 test | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass 54 docs, generated/format/analyze 0 diagnostic, platform/release/operations, 128 Flutter tests và encrypted migration | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [ ] `DATA_MODELS.md` — không đổi data contract
- [x] `SECURITY.md`
- [ ] `SUPABASE_INTEGRATION.md` — không đổi backend contract
- [ ] `DEPLOYMENT.md` — không đổi release command/artifact
- [ ] ADR — không có quyết định kiến trúc dài hạn mới

## Bàn giao

Full local gate pass. Thay đổi chỉ thuộc presentation/lifecycle, không mutate
data; còn chờ branch/default-branch CI và native app-switcher runtime evidence.
