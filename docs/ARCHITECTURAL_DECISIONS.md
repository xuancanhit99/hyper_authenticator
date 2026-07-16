# Quyết định kiến trúc

Tài liệu này lập chỉ mục các quyết định bền vững. Quyết định chi tiết mới được ghi thành record trong `docs/adr`.

## Quyết định đã được code áp dụng

| ID | Quyết định | Trạng thái | Bằng chứng |
|---|---|---|---|
| A-001 | Dùng Flutter và Dart cho client | Đã áp dụng | `pubspec.yaml` và platform runner |
| A-002 | Chia lớp Presentation, Domain, Data theo feature | Đã áp dụng, chưa nhất quán | `lib/features` |
| A-003 | BLoC cho feature state và Provider cho theme | Đã áp dụng | `flutter_bloc` và `ThemeProvider` |
| A-004 | GetIt và Injectable để khởi tạo dependency | Đã áp dụng | Các file `injection_container` |
| A-005 | FlutterSecureStorage cho authenticator record | Đã áp dụng | `AuthenticatorLocalDataSource` |
| A-006 | SharedPreferences cho preference không phải secret | Đã áp dụng | Theme, biometric, sync, Remember Me |
| A-007 | Supabase cho user authentication và remote sync | Đã áp dụng | Auth và sync data source |
| A-008 | `Either` của fpdart tại repository/use-case boundary | Đã áp dụng | Domain và data layer |
| A-009 | GoRouter redirect từ auth và local-lock state | Đã áp dụng | `AppRouter` |

Đã áp dụng không đồng nghĩa hoàn hảo. `PROJECT_STATUS.md` ghi defect trong implementation hiện tại.

## Quyết định cần đưa ra

| ID đề xuất | Quyết định cần có | Lý do |
|---|---|---|
| P-001 | Hỗ trợ offline-only hay bắt buộc Supabase auth? | Lịch sử README và router hiện tại mâu thuẫn |
| P-002 | E2EE key hierarchy, recovery và encrypted format | Cloud secret dạng plaintext chặn release |
| P-003 | Protocol sync atomic, conflict và deletion | Snapshot xóa-rồi-chèn hiện tại có thể mất dữ liệu |
| P-004 | Quyền sở hữu authenticator data khi logout/đổi account | Logout hiện xóa account local |
| P-005 | Một `AccountsBloc` owner hay orchestration tầng repository | Sync và UI resolve instance khác nhau |
| P-006 | Bề mặt password recovery canonical | Mobile deep link và web page đang chồng lấn |
| P-007 | Ma trận platform được hỗ trợ | Có runner ngoài các mục tiêu đã xác minh |
| P-008 | Chiến lược client configuration | `.env` bị ignore nhưng đóng gói như asset |
| P-009 | Tên và identifier sản phẩm | Hyper Authenticator và HyperZ đang bị trộn |
| P-010 | License | Chưa track file license rõ ràng |

## Quy trình ADR

Tạo ADR khi thay đổi:

- trust boundary hoặc cryptographic design;
- data contract local/remote đã persist;
- platform hoặc backend được hỗ trợ;
- ngữ nghĩa phá hủy dữ liệu;
- state ownership hoặc pattern kiến trúc chính;
- dependency có ràng buộc dài hạn.

Các bước:

1. Sao chép `docs/adr/0000-template.md`.
2. Gán số bốn chữ số tiếp theo và slug ngắn.
3. Mô tả context, decision, alternative, consequence, migration, rollback và verification.
4. Đặt trạng thái **Đề xuất**.
5. Lấy phê duyệt của owner.
6. Chuyển sang **Chấp nhận** và thêm record vào chỉ mục này.
7. Đánh dấu record bị thay thế thay vì sửa lại lịch sử.

## Lý do lịch sử

Các lựa chọn hiện tại tối ưu cho một codebase cross-platform, state transition rõ ràng, data source có thể thay thế và backend bootstrap nhanh. Trade-off chính là bảo trì generated code, BLoC boilerplate, khác biệt plugin theo platform, phụ thuộc cấu hình Supabase và yêu cầu boundary test nghiêm ngặt.
