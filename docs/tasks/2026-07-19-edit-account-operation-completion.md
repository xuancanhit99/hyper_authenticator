# Task: Khóa completion của thao tác chỉnh sửa tài khoản

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-07-19
- Owner: canhvx
- Issue hoặc ADR liên quan: Không; hardening presentation state hiện có

## Mục tiêu

Form chỉnh sửa chỉ đóng sau khi đúng update operation đã persist thành công, không
đóng vì reload danh sách/lifecycle và không pop page cuối của GoRouter.

## Ngoài phạm vi

- Không đổi validation, local-vault format, cloud snapshot hoặc Supabase schema.
- Không thay đổi delete-account UX trong task này.

## Acceptance criteria

- [x] `AccountsLoaded` không tự đóng edit route.
- [x] Update persist thành công phát state riêng không chứa account/secret.
- [x] Submit đang chạy bị khóa; lỗi chỉ được gắn với update đang submit.
- [x] GoRouter root trở về `/` thay vì pop page cuối.
- [x] Có regression cho non-default algorithm/digits/period, duplicate submit,
  update success không thuộc form hiện tại và opaque token mismatch.
- [x] Entity, use-case param và mutation event/state stringify không lộ account
  identity, secret, operation token hoặc raw failure message.
- [x] Failure đúng token giữ form và mở lại submit; failure khác không hoàn tất route.
- [x] Full canonical gate và secret scan pass.

## Bằng chứng hiện tại

- Source path: `accounts_bloc.dart`, `accounts_state.dart`, `edit_account_page.dart`.
- Cách tái hiện cũ: mở edit route rồi phát `LoadAccounts`; listener generic
  `AccountsLoaded` gọi `Navigator.pop` dù chưa có update.
- Test mới: `test/features/authenticator/edit_account_route_test.dart`.
- Giả định: một `AccountsBloc` là owner của list và mutation state trong route hiện tại.

## Đánh giá rủi ro

- Lộ credential: success state không mang `AuthenticatorAccount` hoặc secret.
  Mutation event/state override string representation và operation token opaque.
- Mất dữ liệu local: update use case và persistence contract không đổi.
- Mất dữ liệu cloud: không chạm sync hoặc remote schema.
- Migration: không có.
- Rollback: bỏ state update-specific và trả listener cũ; không cần data rollback.
- Tác động platform: Flutter presentation path chung trên sáu target.

## Kế hoạch

- [x] Thêm `AccountUpdateSuccess` và phát trước khi queue reload.
- [x] Khóa submit/lỗi theo operation và navigation route-safe.
- [x] Bind request/success bằng opaque token và redact mutation event/state log.
- [x] Redact entity/use-case param representation mà không đổi serialization.
- [x] Thêm widget regression cho reload, duplicate submit và GoRouter root.
- [x] Cập nhật tài liệu canonical.
- [x] Chạy full gate, secret scan và review diff.
- [ ] Xác minh branch/default-branch CI — bằng chứng bàn giao sau merge.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `flutter test test/features/authenticator/edit_account_route_test.dart` | Pass 6/6 | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass 55 docs, generated/format/analyze, platform/release/operations, 136 Flutter tests và encrypted migration | 2026-07-19 |
| `scripts/agent/check_secrets.sh` | Pass 137 commit, không có leak | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md` — ghi rõ log representation; persisted contract không đổi
- [x] `SECURITY.md`
- [ ] `SUPABASE_INTEGRATION.md` — không đổi backend contract
- [ ] `DEPLOYMENT.md` — không đổi artifact/release command
- [ ] ADR — không có quyết định kiến trúc dài hạn mới

## Bàn giao

Local full gate và secret scan pass. Không có migration hoặc data contract mới;
còn chờ branch/default-branch CI làm bằng chứng đa nền tảng sau commit.
