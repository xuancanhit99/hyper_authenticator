# Đóng các khoảng trống P0 và làm mới Privacy Shield

## Mục tiêu

- loại bỏ đường truy cập `public.synced_accounts` chứa TOTP secret plaintext;
- buộc mọi cập nhật encrypted snapshot sau revision đầu tiên đi qua device-wrap
  protocol đã xác minh, không còn cửa sổ protocol `0` hoặc TOCTOU;
- fail closed khi rotation nhận active device key có membership proof hiện tại
  không hợp lệ;
- bổ sung Web runtime smoke có public config tổng hợp, không dùng credential thật;
- làm lại Privacy Shield theo Material 3, vẫn che opaque và không làm lộ semantics;
- đồng bộ tài liệu canonical với code, migration và bằng chứng test hiện tại.

## Phạm vi không làm trong task này

- không triển khai cryptographic exclusion theo lựa chọn từng thiết bị trong UI;
- không bật E2EE cho Web (Web vẫn là local-only theo threat model hiện tại);
- không thay đổi dữ liệu local của người dùng;
- không chạy migration destructive trên production nếu chưa có backup mới, xác nhận
  row count bằng `0` và preflight rollback.

## Acceptance criteria

- Migration plaintext fail trước mutation khi còn row và drop table khi bảng rỗng;
  remote/restore/health contract không còn coi bảng này là API hợp lệ.
- Legacy publish chỉ tạo snapshot revision đầu tiên; v2 khóa snapshot row và từ
  chối protocol chưa bật. Test có regression cho protocol `0` và concurrent state.
- `prepareRotation` kiểm tra wrapped key + membership proof của mọi active key ở
  generation hiện tại trước khi tạo wrap mới; proof giả/stale không gọi RPC.
- Privacy Shield: frame đầu tiên opaque, static, responsive ở 320px/text scale 200%,
  có một semantics label an toàn và không để child interaction/semantics lọt ra.
- Web CI chạy build configured và browser/runtime smoke phát hiện startup failure,
  không cần Supabase thật.
- Tài liệu canonical dùng nhãn **Đã triển khai**, **Dự kiến**, **Khoảng trống đã
  biết** và không còn claim mâu thuẫn với code/test.

## Rủi ro, migration và rollback

- Drop plaintext là destructive với dữ liệu legacy. Migration dừng với lỗi rõ ràng
  nếu `count(*) > 0`; operator phải backup full + checksum/off-host trước khi chạy.
  Rollback chỉ khôi phục snapshot database đã backup và triển khai release tương thích,
  không bật lại plaintext sync trong client mới.
- Protocol cutoff có thể buộc client cũ nâng cấp/enroll device. Giữ initial publish
  revision `0` để onboarding; không cho client cũ update snapshot đã tồn tại.
- Proof validation có thể làm rotation fail closed khi metadata cũ hỏng; giữ DEK và
  recovery key hiện tại, không ghi partial wrap.
- Web smoke dùng host/key tổng hợp `.invalid`; không ghi secret thật vào artifact/log.

## Kế hoạch xác minh

| Hạng mục | Lệnh/evidence | Kết quả |
|---|---|---|
| Dart/UI | `scripts/agent/check.sh quick` | Pass; analyzer, format, generated DI và focused regression đều xanh |
| Auth/storage/sync/SQL | `scripts/agent/check.sh full` | Pass; 187 Flutter test cùng release/operations/PostgreSQL contract đều xanh |
| Migration | `scripts/supabase/test_encrypted_vault_migration.sh` và `scripts/supabase/test_plaintext_retirement_migration.sh` | Pass; có row-lock/confirm và concurrent-writer regression thật |
| Privacy Shield | `flutter test test/core/security/privacy_shield_test.dart` | Pass 3 test trên light/dark, 320 px, text scale 200%, semantics/interaction và contrast |
| Web | configured build + `scripts/agent/web_runtime_smoke.sh` + `web-deployment/test.sh` | Pass; configured artifact mount engine/local-vault shell, còn build thiếu config bị phát hiện đúng |
| Production | fresh backup, zero-row preflight, migration, remote contract | Pass; table absent, encrypted 36/36, registry 25/25, recovery 8/8, health/restore/off-host và final zero-data audit |

## Nhật ký quyết định

- 2026-07-22: chọn drop `synced_accounts` bằng migration fail-closed sau backup;
  không giữ deny-all table vì nó vẫn làm schema/API cũ sống và dễ bị hiểu nhầm là
  rollback path.
- 2026-07-22: generic vault-key rotation hiện cấp wrap mới cho tất cả active device
  key đã được verify; per-device cryptographic exclusion để backlog riêng.
- 2026-07-22: production apply dùng pre-backup/off-host
  `supabase-20260722T153421Z`, zero-row preflight và post-backup
  `supabase-20260722T155219Z`; full restore rehearsal, encrypted off-host copy,
  health và public HTTPS contracts đều pass.
- 2026-07-22: lượt post-backup đầu tạo artifact hợp lệ nhưng retention fail vì ba
  backup lịch sử thuộc `root:root`. Đã xác minh không có symlink, chuẩn hóa owner
  về service account, giữ mode private và chạy lại thành công với đúng bảy bản.
- 2026-07-22: Auth load post-P0 lượt đầu trả 100/100 HTTP 200 nhưng p95 1.829 giây;
  lượt lặp ngay sau pass p95 285 ms/max 293 ms. Giữ cả hai evidence và tiếp tục
  coi latency transient là rủi ro quan sát, không xóa lượt fail khỏi baseline.
- 2026-07-22: adversarial review bổ sung legacy expected-revision `NULL` guard,
  RLS-safe count và guarded DROP. Production re-apply dùng pre-backup/off-host
  `supabase-20260722T161217Z`; post-backup `supabase-20260722T161534Z`, full
  restore/off-host, health, remote 36/36 và final zero-data audit đều pass.
