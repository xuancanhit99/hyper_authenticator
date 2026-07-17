# Playbook dành cho AI Agent

`AGENTS.md` là operating contract cho toàn repository. Tài liệu này giải thích cách áp dụng contract vào công việc dài hạn.

## Thành phần harness

- `AGENTS.md`: invariant rule và validation matrix.
- `docs/PROJECT_STATUS.md`: baseline đã xác minh và failure đã biết.
- `docs/README.md`: bản đồ tài liệu canonical.
- `docs/tasks`: context task bền vững qua nhiều session.
- `docs/adr`: quyết định kiến trúc bền vững.
- `scripts/agent/context.sh`: định hướng repository an toàn.
- `scripts/agent/doctor.sh`: kiểm tra environment và configuration.
- `scripts/agent/check.sh`: documentation, quick và full gate.
- `supabase/`: upstream pin, non-secret compose overlay, migration và backend contract.
- `scripts/supabase/test_remote_contract.sh`: isolated Auth/RLS integration gate.
- `docs/operations`: runbook backup/restore không chứa secret.

## Bắt đầu session

Chạy:

    git status --short --branch
    scripts/agent/context.sh
    scripts/agent/doctor.sh

Sau đó đọc:

1. `AGENTS.md`.
2. `PROJECT_STATUS.md`.
3. Tài liệu canonical của subsystem.
4. Source, test và generated boundary gần nhất.

Không bắt đầu chỉ từ feature claim trong README.

## Task record

Với công việc không đơn giản, tạo:

    docs/tasks/YYYY-MM-DD-short-name.md

từ `docs/tasks/TEMPLATE.md`.

Giữ record ngắn gọn và cập nhật:

- objective và non-goal;
- acceptance criteria;
- evidence và assumption;
- contract bị ảnh hưởng;
- implementation checkpoint;
- command và kết quả;
- follow-up.

Task record không thay thế tài liệu canonical. Khi hoàn thành, chuyển sự thật bền vững vào tài liệu canonical rồi đóng hoặc archive task note.

## Vòng lặp làm việc

### 1. Định khung

- Nêu lại outcome mà user có thể thấy.
- Xác định tác động bảo mật và nguy cơ mất dữ liệu.
- Liệt kê bằng chứng cần có.
- Chọn validation gate.

### 2. Khảo sát

- Tìm bằng `rg` và `rg --files`.
- Truy vết từ UI qua BLoC, use case, repository tới data source.
- Kiểm tra registration lifecycle khi instance đi qua nhiều feature.
- Kiểm tra cấu hình platform và backend.
- Phân biệt behavior hiện tại với comment hoặc planned doc.

### 3. Lập kế hoạch

- Dùng bước nhỏ, có thể hoàn tác.
- Viết test trước security-critical fix.
- Xác định migration và rollback cho persisted data.
- Chỉ yêu cầu owner quyết định khi lựa chọn làm thay đổi đáng kể product behavior.

### 4. Triển khai

- Bảo toàn thay đổi không liên quan.
- Tránh refactor rộng trong bug fix.
- Không sửa generated DI output bằng tay.
- Không log credential khi thêm diagnostic.
- Cập nhật tài liệu khi contract thay đổi.

### 5. Xác minh

- Chạy test hẹp nhất trong lúc lặp.
- Chạy harness gate bắt buộc khi hoàn tất.
- Chạy platform hoặc Supabase integration check cho boundary change.
- So sánh Git diff với scope task.

### 6. Bàn giao

Báo cáo:

- outcome trước;
- file và behavior đã thay đổi;
- tác động migration hoặc compatibility;
- kết quả xác minh chính xác;
- rủi ro còn lại;
- thay đổi không liên quan có được bảo toàn hay không.

## Tiêu chuẩn bằng chứng

Bằng chứng mạnh:

- deterministic test pass;
- runtime output tái hiện được;
- truy vết source trực tiếp;
- kiểm tra generated manifest hoặc compiled artifact;
- backend integration test isolated.

Bằng chứng yếu:

- comment cũ;
- feature list trong README;
- planned design document;
- thư mục runner;
- package tồn tại nhưng không có active call path.

Đánh nhãn rõ nội dung suy luận.

## Protocol cho task nhạy cảm về bảo mật

Với auth, TOTP, secure storage, sync, crypto, recovery hoặc RLS:

1. Xác định asset và attacker.
2. Định nghĩa trust boundary.
3. Viết failure case và abuse case.
4. Thêm negative test.
5. Định nghĩa migration, rollback và key/data recovery.
6. Xác nhận log và fixture đã redact.
7. Cập nhật `SECURITY.md`.
8. Thêm ADR khi quyết định dài hạn thay đổi.

Không ship thiết kế crypto một phần sau user toggle thông thường.

## Quản lý context

Khi task kéo dài qua nhiều session:

- giữ sự thật bền vững trong task record;
- tham chiếu file path và symbol, không copy source dài;
- ghi command gần nhất và kết quả;
- tách quyết định chưa xử lý khỏi implementation TODO;
- không lưu secret hoặc token tạm thời;
- chỉ dùng `PROJECT_STATUS.md` cho sự thật cấp repository đã xác minh.

## Câu hỏi tự review

Trước khi tuyên bố hoàn tất:

- Thay đổi có thể làm mất account local hoặc cloud không?
- Secret có thể tới log, backend field, test output hoặc screenshot không?
- Retry có duplicate hoặc delete dữ liệu không?
- Record cũ còn load được không?
- UI và background component có dùng cùng state owner không?
- Lock đã cấu hình có fail closed không?
- Server policy có version control và negative test không?
- Behavior và tài liệu canonical có thay đổi cùng nhau không?

## Điều kiện dừng để xin quyết định

Dừng và yêu cầu owner quyết định khi:

- phải chọn offline hay mandatory account;
- quyền sở hữu dữ liệu khi logout thay đổi;
- E2EE recovery policy chưa quyết định;
- migration có thể xóa plaintext hoặc ciphertext không thể đảo ngược;
- claim platform support thay đổi;
- cấu hình legal, store hoặc external production cần phê duyệt.

Tiếp tục độc lập với khảo sát read-only, test, safe refactor và thay đổi nằm trong contract đã chấp nhận.
