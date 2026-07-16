# Roadmap

Đây là roadmap xử lý theo rủi ro, không phải cam kết thời gian giao hàng.

## Giai đoạn 0 — Thiết lập baseline đáng tin cậy

- Thêm workflow `.env` development an toàn để test build được.
- Thay template đã comment bằng test thật.
- Sửa analyzer warning và deprecated API hiện tại mà không gây behavior churn.
- Thêm CI với Flutter version được pin.
- Thêm license rõ ràng và tên sản phẩm nhất quán.
- Thêm Supabase schema và RLS migration có version control.

Exit criteria: quick và full harness gate chạy deterministic trong CI.

## Giai đoạn 1 — Bảo vệ tính đúng đắn local

- Giữ algorithm, digits và period khi create và restore từ sync.
- Countdown nhận biết period.
- Validate Base32, algorithm, digits và period tại domain boundary.
- Xóa log chứa secret.
- Định nghĩa recovery cho secure-storage index.
- Tách storage authentication/session khỏi authenticator storage.
- Quyết định và triển khai quyền sở hữu dữ liệu khi logout/đổi account.
- Làm app-lock error fail closed.

Exit criteria: luồng TOTP và lock local có unit, BLoC, widget và device integration coverage.

## Giai đoạn 2 — Thiết kế lại synchronization

- Chấp nhận ADR cho identity, deletion, conflict, concurrency và atomic publication.
- Thay xóa-rồi-chèn bằng protocol atomic, idempotent.
- Dùng một account-state owner rõ ràng.
- Thêm tombstone hoặc snapshot revision model có tài liệu.
- Thêm test interrupted write, retry và hai thiết bị.

Exit criteria: không network/concurrency failure giả lập nào làm mất snapshot hợp lệ gần nhất.

## Giai đoạn 3 — Triển khai E2EE

- Chấp nhận ADR về key hierarchy và recovery.
- Triển khai authenticated encryption có version.
- Thêm onboarding đa thiết bị và recovery.
- Migrate row plaintext an toàn.
- Xóa field plaintext và xác minh không secret nào tới remote log hoặc row.

Exit criteria: backend-blind secret storage được chứng minh bằng test và review.

## Giai đoạn 4 — Hoàn thiện auth và product flow

- Quyết định có hỗ trợ offline-only hay không.
- Chọn một password-recovery surface.
- Hoàn thiện deep link và recovery test.
- Thêm data export, deletion và retention behavior hướng tới user.
- Thêm localization và accessibility baseline.

Exit criteria: product behavior, privacy policy và store declaration khớp nhau.

## Giai đoạn 5 — Hardening platform release

- Android signing, permission, backup và Play check.
- iOS signing, Keychain, deep link và TestFlight check.
- macOS entitlement và notarization.
- Quyết định rõ về Web, Windows và Linux support.
- Quy trình release provenance, rollback và incident.

Exit criteria: gate trong `DEPLOYMENT.md` pass cho từng platform được quảng bá.

## Quy tắc chọn việc

Không ưu tiên convenience feature trước các blocker làm lộ credential hoặc mất dữ liệu, trừ khi owner chấp nhận rủi ro rõ ràng. Mỗi roadmap item nên dùng `docs/tasks/TEMPLATE.md` và ghi bằng chứng xác minh.
