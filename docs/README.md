# Bản đồ tài liệu

Thư mục này chứa tài liệu engineering canonical của Hyper Authenticator. Toàn bộ tài liệu được viết bằng tiếng Việt; các thuật ngữ tiếng Anh chuyên ngành được giữ lại khi giúp nội dung chính xác và dễ đối chiếu với code.

## Thứ tự đọc

1. [Trạng thái dự án](PROJECT_STATUS.md) — phần nào đã triển khai, phần nào đang lỗi và check nào đang chạy được.
2. [Thiết kế hệ thống](SYSTEM_DESIGN.md) — kiến trúc runtime và data flow.
3. [Bảo mật](SECURITY.md) — asset, trust boundary, threat và release blocker.
4. [Mô hình dữ liệu](DATA_MODELS.md) — contract serialization local và remote hiện tại.
5. [Phát triển](DEVELOPMENT.md) — thiết lập và command hằng ngày.
6. [Chiến lược kiểm thử](TESTING_STRATEGY.md) — quality gate và coverage bắt buộc.
7. [Tích hợp Supabase](SUPABASE_INTEGRATION.md) — authentication, database contract và RLS.
8. [Deployment](DEPLOYMENT.md) — mức sẵn sàng phát hành và checklist theo platform.

## Tài liệu canonical

| Tài liệu | Mục đích | Loại sự thật |
|---|---|---|
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | Baseline đã xác minh và khoảng trống đã biết | Hiện tại |
| [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md) | Component và flow runtime | Hiện tại |
| [DATA_MODELS.md](DATA_MODELS.md) | Model và serialization shape đã triển khai | Hiện tại |
| [SECURITY.md](SECURITY.md) | Security posture hiện tại và control bắt buộc | Hiện tại + yêu cầu |
| [SUPABASE_INTEGRATION.md](SUPABASE_INTEGRATION.md) | Client contract đã quan sát và server setup bắt buộc | Hiện tại + yêu cầu |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Local workflow có thể tái hiện | Quy trình |
| [TESTING_STRATEGY.md](TESTING_STRATEGY.md) | Test layer và quality gate | Quy trình + mục tiêu |
| [DEPLOYMENT.md](DEPLOYMENT.md) | Release gate theo platform | Quy trình |
| [PRIVACY_POLICY.md](PRIVACY_POLICY.md) | Privacy behavior và phần owner phải điền trước store | Hiện tại + release input |
| [NON_FUNCTIONAL_REQUIREMENTS.md](NON_FUNCTIONAL_REQUIREMENTS.md) | Mục tiêu chất lượng có thể đo | Yêu cầu |
| [E2EE_DESIGN.md](E2EE_DESIGN.md) | Contract mã hóa đầu cuối v1 | Hiện tại + khoảng trống |
| [ROADMAP.md](ROADMAP.md) | Trình tự xử lý theo ưu tiên | Dự kiến |
| [ARCHITECTURAL_DECISIONS.md](ARCHITECTURAL_DECISIONS.md) | Chỉ mục và trạng thái quyết định | Quyết định |
| [AI_AGENT_PLAYBOOK.md](AI_AGENT_PLAYBOOK.md) | Workflow dài hạn cho AI Agent | Quy trình |

Tài liệu theo component:

- [Trang web khôi phục mật khẩu](../reset-password-web/README.md)
- [Backup và khôi phục Supabase legacy](operations/SUPABASE_LEGACY_BACKUP.md)
- [Rollout Supabase E2EE snapshot](operations/SUPABASE_E2EE_ROLLOUT.md)
- [Rollout password recovery](operations/SUPABASE_RECOVERY_ROLLOUT.md)
- [Supabase backend harness](../supabase/README.md)
- [Vận hành Supabase production](operations/SUPABASE_PRODUCTION_OPERATIONS.md)

## Từ vựng trạng thái

- **Đã triển khai:** có trong source và truy vết được tới runtime path.
- **Đã xác minh:** được tái hiện bằng command hoặc test có ghi lại.
- **Dự kiến:** được đề xuất nhưng chưa triển khai.
- **Khoảng trống đã biết:** hành vi đã có nhưng chưa đầy đủ, không an toàn, gây hiểu lầm hoặc chưa xác minh.
- **Release blocker:** phải xử lý trước khi cho phép secret production thật.

## Quy tắc tài liệu

- Mô tả hệ thống hiện tại trước hệ thống mong muốn.
- Đặt thiết kế tương lai trong phần được ghi rõ là **Dự kiến**.
- Liên kết khẳng định với source path khi thực tế.
- Không chứa URL, key, token, mật khẩu, TOTP secret, URI `otpauth` hoặc user ID thật.
- Cập nhật `PROJECT_STATUS.md` khi baseline xác minh thay đổi.
- Cập nhật `DATA_MODELS.md` và `SUPABASE_INTEGRATION.md` trong cùng thay đổi với serialization hoặc schema.
- Thêm ADR cho quyết định kiến trúc, bảo mật hoặc data contract dài hạn.
- Dùng file không có hậu tố ngôn ngữ làm tài liệu canonical; không tạo bản dịch trùng lặp dễ lệch nội dung.

## Task record và decision record

- [Task template](tasks/TEMPLATE.md) — working note cho thay đổi không đơn giản.
- [ADR template](adr/0000-template.md) — template architecture decision record.
- [Quyết định kiến trúc](ARCHITECTURAL_DECISIONS.md) — chỉ mục quyết định đã chấp nhận và đang đề xuất.
