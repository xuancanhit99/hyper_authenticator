# Hướng dẫn đóng góp

Repository xem tài liệu, hành vi bảo mật và data contract là một phần của sản phẩm.

## Trước khi bắt đầu

1. Đọc `AGENTS.md`.
2. Chạy `scripts/agent/context.sh`.
3. Đọc `docs/PROJECT_STATUS.md` và tài liệu canonical của khu vực cần thay đổi.
4. Kiểm tra trạng thái Git và bảo toàn thay đổi không liên quan của người dùng.
5. Với công việc không đơn giản, sao chép `docs/tasks/TEMPLATE.md` thành task note có ngày và ghi scope, rủi ro, cách xác minh.

## Quy trình thay đổi

1. Định nghĩa acceptance criteria có thể quan sát.
2. Thêm hoặc cập nhật test trước khi thay đổi luồng liên quan đến bảo mật hoặc nguy cơ mất dữ liệu.
3. Giữ trách nhiệm của Presentation, Domain và Data tách biệt.
4. Không log TOTP secret, URI `otpauth`, mật khẩu, session token, encryption key, salt hoặc recovery material.
5. Cập nhật output của Injectable khi dependency annotation thay đổi.
6. Cập nhật tài liệu trong cùng thay đổi khi hành vi, cấu hình, data contract hoặc quy trình vận hành thay đổi.
7. Chạy quality gate nhỏ nhất phù hợp, sau đó chạy full gate khi khả thi.

## Quality gate

Chỉ thay đổi tài liệu:

    scripts/agent/check.sh docs

Code Dart hoặc Flutter:

    scripts/agent/check.sh quick

Hành vi, storage, authentication, sync, routing hoặc tích hợp platform:

    scripts/agent/check.sh full

Thay đổi đặc thù platform cũng cần build hoặc test trên platform bị ảnh hưởng. Ghi command và kết quả trong phần bàn giao.

## Quyết định kiến trúc

Thêm ADR khi thay đổi ảnh hưởng đến:

- hình dạng dữ liệu local hoặc remote đã persist;
- ranh giới authentication hoặc authorization;
- encryption hoặc key management;
- quyền sở hữu state management hoặc dependency injection;
- platform được hỗ trợ;
- ngữ nghĩa sync hoặc xóa mang tính phá hủy;
- dependency tạo ra ràng buộc dài hạn cho dự án.

Dùng `docs/adr/0000-template.md` và thêm record mới vào `docs/ARCHITECTURAL_DECISIONS.md`.

## Checklist pull request

- Scope và acceptance criteria rõ ràng.
- Không ghi đè thay đổi không liên quan của người dùng.
- Test bao phủ hành vi thay đổi hoặc đã giải thích phần coverage còn thiếu.
- Không có secret hoặc dữ liệu cá nhân trong code, fixture, log, screenshot hoặc tài liệu.
- Ảnh hưởng đến data migration và rollback đã được ghi lại.
- Tài liệu canonical liên quan đã cập nhật.
- Kết quả analyzer, test và platform check được báo chính xác.
