# Hợp đồng vận hành dành cho AI Agent

File này áp dụng cho toàn bộ repository và là tài liệu đầu tiên mà một AI coding agent phải đọc.

## Sứ mệnh

Cải thiện Hyper Authenticator mà không làm lộ TOTP secret, mất dữ liệu người dùng hoặc mô tả tính năng dự kiến như thể đã được triển khai.

## Thứ tự nguồn sự thật

Khi thông tin mâu thuẫn, dùng thứ tự ưu tiên sau:

1. Test đã chạy và bằng chứng runtime có thể tái hiện.
2. Source code và cấu hình platform hiện tại.
3. `docs/PROJECT_STATUS.md`.
4. Các tài liệu canonical khác được liệt kê trong `docs/README.md`.
5. Comment và ghi chú lịch sử.

Không sao chép khẳng định từ tài liệu cũ sang thay đổi mới khi chưa đối chiếu với code.

## Trình tự bắt buộc khi bắt đầu

1. Chạy `git status --short --branch`.
2. Chạy `scripts/agent/context.sh`.
3. Đọc `docs/PROJECT_STATUS.md`.
4. Đọc tài liệu canonical của subsystem bị tác động.
5. Kiểm tra test và call site lân cận trước khi sửa.
6. Nêu rõ giả định khi bằng chứng chưa đầy đủ.

Các thay đổi có sẵn trong working tree thuộc về người dùng. Không reset, loại bỏ, format hoặc ghi đè thay đổi không liên quan.

## Bản đồ repository

- `lib/main.dart` và `lib/app.dart`: bootstrap, provider và lifecycle.
- `lib/core`: routing, cấu hình, theme và failure dùng chung.
- `lib/features/auth`: xác thực người dùng qua Supabase.
- `lib/features/authenticator`: tài khoản local, TOTP, QR và khóa thiết bị.
- `lib/features/sync`: đồng bộ snapshot qua Supabase.
- `lib/features/settings`: sinh trắc học, điều khiển sync và logout.
- `assets`: font, branding và bản đồ logo authenticator.
- `android`, `ios`, `macos`, `web`, `windows`, `linux`: platform runner.
- `reset-password-web`: trang Supabase recovery tĩnh, tách biệt.
- `docs`: tài liệu product và engineering canonical.
- `scripts/agent`: helper định hướng và quality gate có tính quyết định.

## Bất biến bảo mật

- Xem `secretKey` và mọi URI `otpauth` đầy đủ là credential.
- Không in, log, commit, tải lên issue hoặc đặt credential trong fixture.
- Không thêm service-role key vào Flutter asset, file môi trường hoặc client build.
- Không khẳng định cloud sync là E2EE cho đến khi encryption, key recovery, migration và test được triển khai.
- Thao tác phá hủy dữ liệu phải rõ ràng, có thể khôi phục khi khả thi và được test.
- Logout không được âm thầm xóa dữ liệu authenticator.
- Lỗi local authentication không được vô tình bypass khóa đã cấu hình.
- Phân quyền server cần RLS policy đã deploy; filter `user_id` phía client không phải cơ chế phân quyền.

## Khu vực rủi ro cao hiện tại

Đọc `docs/PROJECT_STATUS.md` trước khi tác động đến:

- cloud secret ở dạng plaintext;
- upload cloud theo kiểu xóa rồi chèn;
- xóa dữ liệu local khi logout;
- làm mất tham số TOTP không phải mặc định khi lưu;
- deep link khôi phục mật khẩu chưa hoàn thiện;
- quyền sở hữu instance giữa `SyncBloc` và `AccountsBloc` của UI;
- thiếu automated test và CI;
- permission, entitlement và release signing của platform chưa hoàn thiện.

## Quy tắc kiến trúc

- UI phát event và render state; UI không sở hữu logic persistence.
- Domain entity và use case không phụ thuộc Flutter widget.
- Data source sở hữu cơ chế storage và network.
- Repository chuyển exception thành typed failure.
- Ưu tiên một BLoC owner cho mỗi stateful resource. Truyền instance hiện có khi cần phối hợp giữa các feature.
- Field đã persist phải round-trip mà không âm thầm bị thay bằng default.
- Mọi thay đổi remote schema cần migration plan, ghi chú compatibility và contract test.
- `injection_container.config.dart` được generate phải khớp annotation và không được sửa thủ công.

## Kỷ luật thay đổi

- Giữ scope hẹp và có thể hoàn tác.
- Chẩn đoán trước khi sửa.
- Với bug, thêm regression test thất bại trên hành vi cũ.
- Với thay đổi bảo mật hoặc storage, ghi lại threat, migration, rollback và failure behavior.
- Không trộn formatting churn với thay đổi hành vi.
- Không sửa file platform được generate nếu thay đổi không yêu cầu.
- Dùng `docs/tasks/TEMPLATE.md` cho công việc nhiều bước trải qua nhiều subsystem.
- Dùng ADR cho quyết định kiến trúc dài hạn.

## Ma trận xác minh

Chỉ thay đổi tài liệu:

    scripts/agent/check.sh docs

Logic Dart hoặc UI:

    scripts/agent/check.sh quick

Auth, storage, sync, routing, dependency injection, plugin hoặc file platform:

    scripts/agent/check.sh full

Ngoài ra, chạy build trên platform đích cho thay đổi đặc thù platform. Nếu baseline failure chặn xác minh, báo chính xác lỗi có sẵn và chạy mọi check không bị ảnh hưởng.

## Contract tài liệu

Cập nhật tài liệu trong cùng thay đổi khi hành vi thay đổi:

- Kiến trúc runtime: `docs/SYSTEM_DESIGN.md`
- Model hoặc serialization: `docs/DATA_MODELS.md`
- Ranh giới bảo mật: `docs/SECURITY.md`
- Supabase contract: `docs/SUPABASE_INTEGRATION.md`
- Thiết lập hoặc command: `docs/DEVELOPMENT.md`
- Test hoặc gate: `docs/TESTING_STRATEGY.md`
- Deployment: `docs/DEPLOYMENT.md`
- Khoảng trống đã xác minh: `docs/PROJECT_STATUS.md`
- Quyết định bền vững: `docs/ARCHITECTURAL_DECISIONS.md` cùng một ADR

Dùng nhãn **Đã triển khai**, **Dự kiến** và **Khoảng trống đã biết**. Không dùng thiết kế ở thì tương lai làm bằng chứng rằng code đã tồn tại.

## Yêu cầu khi bàn giao

Mỗi task hoàn thành phải nêu:

- kết quả;
- file đã thay đổi;
- tác động đến hành vi và data contract;
- command xác minh và kết quả;
- rủi ro hoặc việc cần theo dõi còn lại;
- các thay đổi không liên quan trong working tree có được bảo toàn hay không.
