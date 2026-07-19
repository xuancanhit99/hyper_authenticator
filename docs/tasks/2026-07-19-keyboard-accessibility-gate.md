# Task: Keyboard accessibility gate cho luồng cốt lõi

- Trạng thái: Hoàn tất
- Bắt đầu: 2026-07-19
- Owner: Hyperz
- Issue hoặc ADR liên quan: Không

## Mục tiêu

Người dùng desktop/Web có thể đi qua và kích hoạt các luồng Auth, account list,
manual add-account và sensitive Settings dialog bằng keyboard mà không cần pointer;
destructive dialog phải mặc định fail-safe và Escape phải hủy rõ ràng.

## Ngoài phạm vi

- Không tuyên bố full keyboard audit cho toàn bộ Settings/main navigation hoặc
  focus visualization đặc thù từng hệ điều hành.
- Không thay TalkBack/VoiceOver runtime test.
- Không đổi local vault, E2EE, Supabase schema hoặc credential.

## Acceptance criteria

- [x] Login/register/update/recovery Auth form có focus order tái hiện được.
- [x] Login và manual add-account submit được bằng keyboard.
- [x] Account list cho phép đi theme → add → search → copy TOTP và kích hoạt bằng Enter.
- [x] Recovery/conflict/session dialog mặc định focus **Hủy**, Tab/Shift+Tab tới
  action đúng thứ tự và Escape không kích hoạt destructive action.
- [x] Recovery-key confirmation chỉ focus/enable submit sau khi người dùng xác
  nhận đã lưu key.

## Bằng chứng hiện tại

- Source path: `lib/features/auth`, `lib/features/authenticator/presentation`,
  `lib/features/settings/presentation/widgets`.
- Cách tái hiện: widget test phát Tab/Shift+Tab/Enter/Space/Escape và assert
  primary focus nằm trong control mong đợi.
- Test hiện có: auth navigation, accounts countdown, scanner feedback và Settings
  recovery/conflict/session dialog.
- Giả định: automated focus tree là regression baseline; runtime audit trên OS
  đại diện vẫn là gate riêng.

## Đánh giá rủi ro

- Lộ credential: fixture tổng hợp; helper chỉ đọc focus widget type/debug label,
  không log field value, secret key hoặc recovery key.
- Mất dữ liệu local: không đổi persistence; test repository in-memory.
- Mất dữ liệu cloud: không gọi network hoặc sync.
- Migration: không có.
- Rollback: revert widget/test/docs commit; data contract không đổi.
- Tác động platform: Flutter focus tree dùng chung; Escape fix áp dụng desktop/Web.

## Kế hoạch

- [x] Audit focus tree trên core surface.
- [x] Thêm reusable focus assertion và keyboard regression test.
- [x] Sửa recovery-key dialog để Escape trả kết quả hủy fail-safe.
- [x] Chạy full gate; CI đa nền tảng tiếp tục là merge gate của repository.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Focused Auth/accounts/add-account suite | Pass keyboard focus order và activation | 2026-07-19 |
| Focused Settings dialog suite | Pass 16 test; regression cũ chứng minh Escape từng không trả kết quả | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass 53 docs, generated/format/analyze 0 diagnostic, platform/release/operations, 127 Flutter tests và encrypted migration | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `NON_FUNCTIONAL_REQUIREMENTS.md`
- [x] `TESTING_STRATEGY.md`
- [x] `ROADMAP.md`
- [x] `DATA_MODELS.md` (đã review, không đổi data model)
- [x] `SECURITY.md` (đã review, không đổi trust boundary)
- [x] `SUPABASE_INTEGRATION.md` (đã review, không đổi remote contract)
- [x] `DEPLOYMENT.md` (đã review, không đổi deployment)
- [x] ADR (đã review, không cần quyết định dài hạn)

## Bàn giao

Core keyboard regression và Escape fail-safe đã pass full gate. Không có thay đổi
data/credential contract; runtime keyboard audit toàn bộ Settings/main navigation,
focus visualization từng OS và screen-reader test vẫn cần theo dõi.
