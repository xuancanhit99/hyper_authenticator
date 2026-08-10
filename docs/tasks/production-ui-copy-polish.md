# Task: Hoàn thiện UI và copy cho production

- Trạng thái: Đang thực hiện
- Bắt đầu: 2026-08-10
- Owner: HyperZ
- Issue hoặc ADR liên quan: Không có

## Mục tiêu

Đưa giao diện và nội dung tiếng Việt về mức production: ngắn gọn, nhất quán,
không lộ thuật ngữ implementation hoặc lỗi backend, đồng thời giữ rõ cảnh báo
bảo mật và tác động của thao tác phá hủy.

## Ngoài phạm vi

- Không đổi local vault, account-sync protocol hoặc remote schema.
- Không đổi persisted enum name của visual style.
- Không thêm hoặc loại bỏ tính năng authenticator trong đợt này.

## Acceptance criteria

- [x] UI không hiển thị raw exception, lỗi Supabase hoặc lỗi storage.
- [x] Copy thêm/sửa/nhập/xuất dùng thuật ngữ tiếng Việt đã thống nhất.
- [x] Xóa mã nói rõ tác động tới các thiết bị đang đồng bộ.
- [x] Settings và bộ chọn giao diện gọn, responsive và có preview dễ hiểu.
- [x] Component geometry nhất quán trong cả sáu theme.
- [x] Có visual regression coverage cho viewport đại diện.

## Bằng chứng hiện tại

- Source path: `lib/features`, `lib/core/theme`, `lib/chrome_extension`.
- Cách tái hiện: mở Settings, Add/Edit, Import/Export và các trạng thái lỗi.
- Test hiện có: 206 Flutter test pass ngày 2026-08-10.
- Giả định: tiếng Việt là locale duy nhất của bản phát hành hiện tại.

## Đánh giá rủi ro

- Lộ credential: không thay đổi dữ liệu nhạy cảm; error mapping giảm nguy cơ lộ
  chi tiết exception.
- Mất dữ liệu local: không thay đổi persistence.
- Mất dữ liệu cloud: không thay đổi sync; copy xóa phải phản ánh đúng tombstone.
- Migration: không có data migration; display label không đổi persisted enum.
- Rollback: từng PR độc lập, có thể revert riêng.
- Tác động platform: UI Flutter dùng chung; extension có copy riêng cần audit.

## Kế hoạch

- [x] PR 1: copy P0, error boundary và xác nhận xóa.
- [x] PR 2: Settings và appearance picker.
- [x] PR 3: Add/Edit/Import/Export.
- [x] PR 4: design token và golden visual regression.
- [ ] PR 5: About/Privacy/Support và localization catalog.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `flutter test` baseline | Pass 206/206 | 2026-08-10 |
| Targeted PR 1 regression | Pass 60/60 | 2026-08-10 |
| `scripts/agent/check.sh full` | Pass, 213 Flutter test + backend/release/infra | 2026-08-10 |
| Targeted PR 2 UI/a11y | Pass 13/13, gồm 6 theme ở 320px + text scale 200% | 2026-08-10 |
| `scripts/agent/check.sh quick` + `flutter test` PR 2 | Pass, analyze 0 issue và 213/213 test | 2026-08-10 |
| Targeted PR 3 Add/Edit/Import/Export | Pass 41/41, gồm fresh-auth, expiry, atomic import và a11y | 2026-08-10 |
| `scripts/agent/check.sh full` PR 3 | Pass, 215 Flutter test + migration/release/infra harness | 2026-08-10 |
| Theme geometry + golden PR 4 | Pass 13/13, đủ 6 palette và 6 ảnh 390 × 844 trên macOS | 2026-08-10 |
| Linux golden PR 4 | 6 ảnh 390 × 844 tạo bằng Flutter 3.44.6 trên CI và đã review trực quan | 2026-08-10 |
| `scripts/agent/check.sh quick` + `flutter test` PR 4 | Pass, analyze 0 issue và 223/223 test | 2026-08-10 |
| `scripts/agent/check.sh full` PR 4 sau thêm baseline Linux | Pass, 223 Flutter test + migration/release/infra harness | 2026-08-10 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [ ] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [ ] `SUPABASE_INTEGRATION.md`
- [ ] `DEPLOYMENT.md`
- [ ] ADR

## Bàn giao

Cập nhật sau từng PR với file thay đổi, compatibility, gate và rủi ro còn lại.
