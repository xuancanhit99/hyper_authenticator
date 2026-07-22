# Engineering task record

Dùng task record cho công việc nhiều bước, đặc biệt khi kéo dài qua nhiều session hoặc ảnh hưởng security, storage, sync, routing, backend contract hay nhiều platform.

Task record là **historical snapshot tại thời điểm task được thực hiện**, không phải
nguồn sự thật hiện tại. Claim về source, production deploy, test count, dependency
hoặc risk trong task cũ có thể đã bị supersede; luôn đối chiếu
`docs/PROJECT_STATUS.md`, canonical subsystem doc, code và runtime evidence theo
thứ tự trong `AGENTS.md`. Không sửa lại lịch sử để làm nó trông như hiện trạng;
thay vào đó ghi kết quả cuối và link tới quyết định/tài liệu canonical mới.

Quy tắc đặt tên:

    YYYY-MM-DD-short-name.md

Tạo từ `TEMPLATE.md`. Giữ working note khách quan, ngắn gọn. Không chứa credential hoặc dữ liệu production được sao chép.

Khi hoàn thành:

- chuyển sự thật bền vững vào tài liệu canonical;
- ghi kết quả xác minh cuối;
- đánh dấu task hoàn tất;
- nêu rõ follow-up chưa xử lý;
- xóa scratch note thuần túy nếu không có giá trị lịch sử.
