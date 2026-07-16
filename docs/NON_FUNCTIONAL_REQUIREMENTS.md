# Yêu cầu phi chức năng

Mục tiêu có nhãn **Đề xuất** chưa được đo hoặc enforce.

## Bảo mật

Bắt buộc:

- Không TOTP secret dạng đọc được nào rời client khi sync production.
- Không credential nào xuất hiện trong log, analytics, crash report, screenshot hoặc fixture.
- Cross-user Supabase test từ chối mọi operation.
- App lock đã cấu hình fail closed khi plugin hoặc routing error.
- Không production artifact nào chứa service-role hoặc server secret.
- Mọi finding bảo mật Critical và High được xử lý trước release.

## Tính đúng đắn và độ tin cậy

Bắt buộc:

- TOTP output khớp RFC 6238 hoặc known-answer vector tương đương cho algorithm được hỗ trợ.
- Mọi account field round-trip qua local storage.
- Sync bị gián đoạn không thể phá hủy snapshot local/cloud hợp lệ gần nhất.
- Merge và deletion semantic deterministic và được ghi lại.
- Retry idempotent.
- Schema hoặc encrypted-format version không được hỗ trợ phải fail mà không ghi đè dữ liệu hợp lệ.

## Tính sẵn sàng

Cần quyết định sản phẩm: offline-only access hay Supabase authentication bắt buộc.

Nếu chấp nhận offline core use, việc xem TOTP phải tiếp tục được khi mất network sau local unlock. Nếu vẫn bắt buộc auth, dependency và outage behavior phải được công bố.

## Hiệu năng

Mục tiêu ban đầu đề xuất trên thiết bị mobile tầm trung đại diện:

- danh sách account cache hiển thị trong 500 ms sau khi app shell sẵn sàng;
- tạo TOTP dưới 10 ms mỗi account ở percentile 95 với 100 account;
- scroll danh sách vẫn responsive với 500 account;
- không có network hoặc secure-storage loop block UI thread;
- tiến trình sync có thể quan sát và cancel.

Đo thực tế trước khi nhận các giá trị này làm release SLO.

## Quyền riêng tư

Bắt buộc:

- Data inventory khớp privacy policy.
- Cloud sync do user kích hoạt được phân biệt rõ với local storage.
- Hành vi xóa account và retention được ghi lại.
- Giảm tối đa dữ liệu cá nhân trong log và support workflow.
- Công bố third-party service và hosted dependency.

## Usability và accessibility

Mục tiêu đề xuất:

- mọi critical flow dùng được bằng screen reader;
- text tuân theo system scaling mà không bị cắt;
- action không phụ thuộc riêng vào màu;
- destructive action giải thích chính xác tác động dữ liệu;
- feedback copy không làm lộ secret đã sao chép;
- định nghĩa localization strategy trước khi thêm hard-coded text.

## Khả năng bảo trì

Bắt buộc:

- Tài liệu canonical cập nhật cùng behavior.
- Không có generated DI drift.
- Defect mới có regression test.
- Persisted contract có version trước incompatible change.
- Thay đổi kiến trúc có ADR.
- Static-analysis diagnostic không tăng khi thiếu lý do rõ ràng.

## Tính portable

Một platform chỉ được hỗ trợ sau khi:

- plugin cần thiết tương thích;
- permission và entitlement đúng;
- secure-storage và local-auth behavior được test;
- release build, install, upgrade và rollback pass;
- limitation được ghi lại.

Có runner không đồng nghĩa được hỗ trợ.

## Observability

Đề xuất:

- structured event category với redaction ở boundary;
- không có raw auth hoặc sync payload;
- correlation ID không làm lộ user/account identity;
- actionable error class cho auth, storage, network, schema và crypto;
- crash reporting opt-in với retention và provider được ghi rõ.

## Recovery

Bắt buộc trước production:

- recovery khi local storage không nhất quán;
- rollback remote snapshot;
- policy key loss và E2EE recovery;
- quyết định account export hoặc backup;
- incident response khi credential hoặc backend bị compromise.

## Cách enforce

Mỗi requirement cuối cùng phải map tới một hoặc nhiều:

- automated test;
- CI rule;
- platform release checklist;
- security review;
- operational monitor;
- accepted risk có owner và thời hạn.
