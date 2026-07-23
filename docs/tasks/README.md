# Engineering task record

Dùng task record cho công việc nhiều bước, đặc biệt khi kéo dài qua nhiều session hoặc ảnh hưởng security, storage, sync, routing, backend contract hay nhiều platform.

Task record là working note tạm, không phải nguồn sự thật hiện tại. Luôn đối chiếu
`docs/PROJECT_STATUS.md`, canonical subsystem doc, code và runtime evidence theo
thứ tự trong `AGENTS.md`.

Quy tắc đặt tên:

    YYYY-MM-DD-short-name.md

Tạo từ `TEMPLATE.md`. Giữ working note khách quan, ngắn gọn. Không chứa credential hoặc dữ liệu production được sao chép.

Khi hoàn thành:

- chuyển sự thật bền vững vào tài liệu canonical;
- ghi kết quả xác minh cuối;
- merge cùng source tương ứng;
- nêu rõ follow-up chưa xử lý;
- xóa task record khỏi active tree; Git history giữ audit trail.
