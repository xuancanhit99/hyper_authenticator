# ADR-0021: Private Realtime chỉ làm tín hiệu đồng bộ

- Trạng thái: Chấp nhận
- Ngày: 2026-08-05
- Owner: HyperZ
- Bổ sung: ADR-0020
- Bị thay thế bởi:

## Bối cảnh

ADR-0020 đã tự động đồng bộ khi đăng nhập, local mutation, app resume, pull to
refresh hoặc retry. Thiết bị đang foreground nhưng idle không biết một thiết bị
khác vừa thay đổi cloud cho tới trigger kế tiếp.

`public.authenticator_accounts` cố ý không cấp direct `SELECT` cho client. Bật
Postgres Changes trực tiếp sẽ làm rộng authorization boundary và có thể gửi
remote row metadata không cần thiết.

## Quyết định

Dùng Supabase private Broadcast làm best-effort wake-up signal:

- topic là `account-sync:<auth.uid()>`;
- chỉ backend trigger được phát event `account-sync-changed`;
- payload chỉ chứa protocol version/id do Realtime sinh, không chứa account ID,
  revision, issuer, account name, Vault reference, TOTP secret hoặc full row;
- `realtime.messages` chỉ có `SELECT` policy cho authenticated user khi topic
  khớp chính xác `auth.uid()` và extension là `broadcast`; không tạo client
  `INSERT` policy;
- client subscribe private channel theo session hiện hành. Khi nhận signal hoặc
  channel reconnect, client debounce rồi gọi sync engine ADR-0020;
- logout/account switch hủy subscription cũ trước khi mở subscription mới.

Realtime không trở thành data protocol. RPC list/upsert/delete, ownership,
fingerprint, CAS và tombstone tiếp tục là nguồn sự thật.

Realtime 2.102.3 kiểm tra quyền join bằng temporary probe row chỉ có `topic` và
`extension`; field `private` của probe là `NULL`. Vì vậy policy không kiểm tra
column `messages.private`. Privacy được bắt buộc bởi private channel join và
database trigger luôn gọi `realtime.send(..., true)`. Corrective migration
`20260805010000_fix_account_sync_realtime_authorization.sql` khóa contract này.

## Phương án đã cân nhắc

### Postgres Changes trên `authenticator_accounts`

Không chọn vì cần mở quyền đọc/RLS trực tiếp cho subscribing role, coupling
client với row schema và authorization theo subscriber đắt hơn khi scale.

### Gửi account payload/revision qua Broadcast

Không chọn vì message/replay/log có thể mở thêm disclosure surface. Signal trống
đủ để client gọi full sync bounded.

### Foreground polling định kỳ

Không chọn làm mặc định vì tạo request/pin ngay cả khi không có thay đổi. Resume
và manual refresh vẫn là fallback khi Realtime mất message.

## Hệ quả

### Tích cực

- Thiết bị foreground nhận thay đổi từ thiết bị khác gần realtime.
- Không thay đổi Vault encryption/trust boundary hoặc direct table ACL.
- Mất WebSocket/message không làm mất dữ liệu; lần full sync kế tiếp tự bù.

### Tiêu cực

- Mỗi mutation có thể làm chính thiết bị phát sinh thêm một read-only sync.
- Background delivery phụ thuộc OS; không được hứa đồng bộ tức thời khi app bị
  suspend.
- Realtime connection/RLS/trigger thêm bề mặt vận hành cần health/contract test.

## Bảo mật

Không log event payload, token hoặc topic đầy đủ. Client không được quyền phát
Broadcast. Policy phải fail closed với anonymous, topic khác user và extension
khác broadcast. Không thêm `authenticator_accounts` vào Postgres Changes
publication.

## Failure behavior và rollback

Channel error không làm sync state thất bại vì RPC/local-first vẫn hoạt động.
Reconnect chạy full sync để bù event đã mất. Rollback client chỉ bỏ subscription;
rollback database drop trigger/function/policy, không đụng account/Vault data.

## Xác minh

- Migration contract: payload allowlist, private topic, trigger, policy và
  direct-table ACL.
- BLoC test: subscribe/session switch/logout, debounce và reconnect.
- Remote two-user test: user chỉ join topic của mình; signal không chứa secret.
- Platform runtime: thiết bị B foreground nhận mutation của thiết bị A.

Production evidence ngày 05-08-2026: remote contract pass 26/26, iOS Simulator
pass remote-only upsert/delete không refresh thủ công, test fixture cleanup = 0;
pre/post backup đều restore rehearsal và encrypted off-host verify thành công.
