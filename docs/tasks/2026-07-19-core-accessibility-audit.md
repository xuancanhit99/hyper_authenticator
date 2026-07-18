# Task: Audit accessibility cho luồng cốt lõi

- Trạng thái: Đang thực hiện
- Bắt đầu: 2026-07-19
- Owner: Hyperz
- Issue hoặc ADR liên quan: Không

## Mục tiêu

Auth, danh sách TOTP và form thêm tài khoản có accessible name rõ ràng, dùng được
ở system text scale 200% trên viewport mobile hẹp và không phát sinh tap target
nhỏ hơn baseline Flutter có thể kiểm tra tự động.

## Ngoài phạm vi

- Không tuyên bố TalkBack/VoiceOver hoặc accessibility audit trên thiết bị thật đã pass.
- Không đổi local vault, TOTP serialization, E2EE hoặc remote schema.
- Không redesign toàn bộ visual system hoặc thêm localization thứ hai.

## Acceptance criteria

- [x] Password visibility, tìm kiếm và account action có accessible name tiếng Việt.
- [x] TOTP copy action công bố issuer/account/code/countdown mà không công bố secret key.
- [x] Auth và account list không overflow ở text scale 200% trên viewport 320×640.
- [x] Core surface pass labeled tap target và Android 48×48 tap target guideline.
- [x] Feedback copy/countdown và tiêu đề Add Account không còn tiếng Anh.

## Bằng chứng hiện tại

- Source path: `lib/features/auth`, `lib/features/authenticator/presentation`.
- Cách tái hiện: widget test với semantics enabled, text scale 200% và viewport 320×640.
- Test hiện có: auth navigation, account countdown và scanner feedback.
- Giả định: automated guideline là baseline; screen reader/device audit vẫn là gate riêng.

## Đánh giá rủi ro

- Lộ credential: semantics được phép công bố TOTP đang hiển thị nhưng tuyệt đối không
  chứa `secretKey` hoặc URI `otpauth`.
- Mất dữ liệu local: không đổi persistence hoặc destructive action.
- Mất dữ liệu cloud: không đổi sync/schema.
- Migration: không có.
- Rollback: revert widget/test/docs commit; data không đổi.
- Tác động platform: Flutter UI dùng chung; automated widget evidence, không thay device evidence.

## Kế hoạch

- [x] Audit code và official Flutter accessibility guidance.
- [x] Thêm regression test cho semantics, text scaling và tap target.
- [x] Sửa Auth/Accounts/Add Account trong phạm vi test tái hiện.
- [ ] Chạy quick/full gate và CI đa nền tảng.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Source audit | Thiếu tooltip password/search; countdown/copy/Add Account còn English; auth/account row chưa có text-scale regression | 2026-07-19 |
| Regression test trên behavior cũ | Fail: login overflow 630/433 px, account row overflow 74 px, thiếu semantics và còn English | 2026-07-19 |
| Focused widget suite | Pass 13 test; ba surface pass labeled/48×48 guideline và text scale 200% | 2026-07-19 |
| `scripts/agent/check.sh quick` | Pass docs/generated/format/analyze, 0 diagnostic | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass 52 docs, generated/format/analyze/platform/release/operations, 109 Flutter test và encrypted migration | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `NON_FUNCTIONAL_REQUIREMENTS.md`
- [x] `TESTING_STRATEGY.md`
- [ ] `SYSTEM_DESIGN.md` (không đổi runtime architecture)
- [ ] `DATA_MODELS.md` (không đổi data model)
- [ ] `SECURITY.md` (không đổi trust boundary)
- [ ] `SUPABASE_INTEGRATION.md` (không đổi remote contract)
- [ ] `DEPLOYMENT.md` (không đổi deployment)
- [ ] ADR (không cần quyết định kiến trúc dài hạn)

## Bàn giao

Đang thực hiện. Bàn giao phải nêu test/guideline pass, giới hạn device audit và xác
nhận không đổi data contract hoặc credential boundary.
