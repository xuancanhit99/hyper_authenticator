# Yêu cầu phi chức năng

Mục tiêu có nhãn **Đề xuất** chưa được đo hoặc enforce.

## Bảo mật

Bắt buộc:

- Không TOTP secret dạng đọc được nào rời client khi sync production.
- Không credential nào xuất hiện trong log, analytics, crash report hoặc fixture.
- Background/app-switcher snapshot phải được che khi app không ở `resumed`.
- Active screenshot/recording khi foreground phải có platform threat model và
  accepted risk rõ ràng; không được tuyên bố đã chặn nếu chưa có native runtime gate.
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

**Đã quyết định:** TOTP local hoạt động không cần Supabase configuration, tài khoản
hoặc network. Auth/backend outage không được chặn xem mã sau local unlock. Backup
cloud là capability tùy chọn và phải fail độc lập với local vault.

## Hiệu năng

Budget backend đã enforce cho release regression, chưa phải SLA người dùng:

- Supabase Auth public health: 100 request, concurrency 10, HTTP 200 tuyệt đối,
  p95 không quá 1.000 ms và request chậm nhất không quá 2.000 ms;
- `scripts/supabase/test_auth_load_budget.sh` fail closed khi lỗi HTTP hoặc vượt
  ngưỡng, đồng thời hỗ trợ interval giữa batch đã có contract test để chạy soak
  bảo thủ; production-scale workload vẫn là mục tiêu riêng.

Evidence 19-07-2026: lượt soak đầu đạt 900/900 và p95 292 ms nhưng fail strict max
do một tail spike 3.648 ms. Sau khi deploy timing allowlist ở NPM, lượt lặp cùng
pacing pass 900/900 trong 1.135 giây, p95 289 ms và max 590 ms. Slowest request có
DNS 3/TCP 88/TLS 200/TTFB 589 ms; NPM request/upstream tương ứng chỉ 70/67 ms.
Toàn cửa sổ proxy có p95 28/25 ms, max 244/244 ms, 0 non-200. Baseline cuối pass
100/100, p95 424/max 436 ms. Đây là regression evidence, chưa phải SLA hoặc
production-scale workload.

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
- Backup cloud do user kích hoạt được phân biệt rõ với local storage.
- Hành vi xóa account và retention được ghi lại.
- Giảm tối đa dữ liệu cá nhân trong log và support workflow.
- Công bố third-party service và hosted dependency.

## Usability và accessibility

Baseline automated đã triển khai cho Auth, danh sách TOTP, form thêm account và
các dialog Settings nhạy cảm:

- control có tap action pass labeled tap target và Android 48×48 guideline;
- password visibility, tìm kiếm, copy TOTP và account action có accessible name
  tiếng Việt;
- viewport 320×640 ở system text scale 200% không overflow;
- semantics của account copy chỉ công bố issuer, account, TOTP đang hiển thị và
  countdown; không công bố secret key hoặc URI `otpauth`.
- WCAG text contrast pass trên light/dark theme cho core surface và sensitive
  Settings dialog;
- Settings recovery import/key confirmation, sync conflict và session-revoke
  dialog pass viewport 320×640, text scale 200%, tap-target, semantics và contrast;
- keyboard regression bao phủ Auth forms, account theme/add/search/copy, manual
  add-account và sensitive dialog bằng Tab/Shift+Tab/Enter/Space/Escape.

Mục tiêu còn lại:

- chạy TalkBack/VoiceOver, full Settings/main-navigation keyboard/focus audit và
  focus visualization trên runtime đại diện;
- mở rộng text scaling/guideline test sang các Settings surface và mọi trạng thái
  lỗi chưa nằm trong baseline trên;
- action không phụ thuộc riêng vào màu;
- destructive action giải thích chính xác tác động dữ liệu;
- feedback copy không làm lộ secret đã sao chép;
- reduced motion và active screenshot/recording review trên platform đại diện;
  lifecycle privacy shield đã có automated regression.

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
- account export/import có format, reauthentication và rollback policy;
- incident response khi credential hoặc backend bị compromise.

## Cách enforce

Mỗi requirement cuối cùng phải map tới một hoặc nhiều:

- automated test;
- CI rule;
- platform release checklist;
- security review;
- operational monitor;
- accepted risk có owner và thời hạn.
