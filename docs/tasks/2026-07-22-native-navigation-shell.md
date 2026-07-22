# Task: Navigation shell native theo platform

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-07-22
- Owner: AI Agent
- Issue hoặc ADR liên quan: Không

## Mục tiêu

Đổi tab Tài khoản/Cài đặt không còn chạy full-page transition, giữ state riêng
của từng tab và vẫn giữ `/` cùng `/settings` làm URL canonical.

## Ngoài phạm vi

- Không thay page transition native của trang Auth, Thêm/Sửa tài khoản hoặc dialog.
- Không đổi app-lock, vault, TOTP hay cloud data contract.

## Acceptance criteria

- [x] Main navigation dùng `StatefulShellRoute.indexedStack`.
- [x] Đổi tab không tạo full-page transition và URL vẫn cập nhật.
- [x] State của tab đã thăm được giữ khi chuyển qua lại.
- [x] `MainNavigationPage` không phát lại local-auth check khi đổi tab.
- [x] Android emulator runtime smoke xác minh chuyển tab cập nhật UI và không crash.

## Bằng chứng hiện tại

- Source path: `lib/core/router/app_router.dart`,
  `lib/features/main_navigation/presentation/pages/main_navigation_page.dart`.
- Cách tái hiện: đổi `/` sang `/settings` bằng bottom navigation trên Android.
- Test hiện có: URL/tab mapping và device integration chuyển Settings/Accounts.
- Giả định: transition native của route phân cấp vẫn do `MaterialPage` chọn theo
  platform; shell page dùng `NoTransitionPage` để không giữ hai
  `StatefulNavigationShell` có cùng `GlobalKey` khi app-lock redirect liên tiếp;
  startup/lock là overlay child trên root navigator để shell không bị
  re-enter.

## Đánh giá rủi ro

- Lộ credential: Không; không đọc hoặc render thêm TOTP secret.
- Mất dữ liệu local: Không; không đổi persistence.
- Mất dữ liệu cloud: Không; không đổi sync.
- Migration: Không có data migration.
- Rollback: revert router, shell page, test và tài liệu trong cùng commit.
- Tác động platform: URL/deep link phải giữ trên Web; back gesture và page
  transition phân cấp phải tiếp tục dùng implementation native của Flutter.

## Kế hoạch

- [x] Xác định transition mặc định và nguyên nhân branch bị thay như full page.
- [x] Refactor main routes thành hai stateful branches.
- [x] Thêm regression widget test cho URL, state retention và animation contract.
- [x] Cập nhật tài liệu canonical và chạy full gate.
- [x] Chạy Android runtime smoke không phá hủy vault.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `flutter test test/core/router/app_redirect_policy_test.dart` | Pass 8/8 baseline | 2026-07-22 |
| Focused router tests | Pass 8/8 | 2026-07-22 |
| `scripts/agent/check.sh full` | Pass toàn bộ, 186 Flutter tests và PostgreSQL migration contract | 2026-07-22 |
| Android emulator build/run + two tab taps | Build/install/Supabase init/UI label pass, no app crash; headless SwiftShader jank không dùng làm production perf evidence | 2026-07-22 |
| Linux/Windows local-vault lifecycle smoke | Baseline phát hiện duplicate `StatefulNavigationShell` `GlobalKey` khi redirect lock liên tiếp; đã xử lý bằng `NoTransitionPage`, không đổi vault/data contract | 2026-07-22 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `TESTING_STRATEGY.md`
- [x] `DATA_MODELS.md` — không tác động
- [x] `SECURITY.md` — không đổi security boundary
- [x] `SUPABASE_INTEGRATION.md` — không tác động
- [x] `DEPLOYMENT.md` — không tác động
- [x] ADR — không cần quyết định dài hạn mới

## Bàn giao

Đã triển khai trên branch `codex/native-navigation-shell`. Không có data migration;
physical Android visual smoothness vẫn nên được owner xác nhận trên thiết bị khi
NotificationShade đóng và app ở foreground.
