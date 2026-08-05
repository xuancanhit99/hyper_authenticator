# ADR-0019: Minimal E2EE với một recovery path

- Trạng thái: Chấp nhận
- Ngày: 2026-08-02
- Owner: HyperZ
- Thay thế: ADR-0008, ADR-0011, ADR-0012, ADR-0013, ADR-0018
- Bị thay thế bởi: ADR-0020

## Bối cảnh

Ứng dụng đang cung cấp đồng thời recovery key cloud, device-specific HPKE wrap,
vault/recovery-key rotation, auth-session management và file `.hyauth`. Các lớp
này tạo nhiều nghìn dòng protocol/UI/test nhưng không tạo trải nghiệm đơn giản
như Google Authenticator; một phần device/rotation code không có runtime entry
point trong primary Settings.

## Quyết định

Giữ local-first và một cloud snapshot AES-256-GCM. Mỗi Supabase user có một DEK
trong platform secure storage và một HA1 recovery key do người dùng giữ để wrap
DEK. Backend chỉ giữ ciphertext, wrapped DEK và revision CAS.

Xóa hoàn toàn portable `.hyauth`, device/session registry, device-specific HPKE
wrap, recovery/vault-key rotation và in-app session management. Khi recovery key
có nguy cơ lộ, hành vi duy nhất là xóa remote snapshot rồi thiết lập cloud lại
với DEK/recovery key mới.

## Phương án đã cân nhắc

### Local-only

Đơn giản và giảm attack surface nhất nhưng không khôi phục được khi mất thiết bị.
Không chọn vì cloud recovery là capability product cần giữ.

### Cloud server-decryptable như account sync thông thường

Ẩn recovery key khỏi người dùng nhưng Supabase compromise có thể lộ toàn bộ TOTP
secret. Không chọn vì phá trust boundary của authenticator.

### Giữ device-specific protocol hiện tại

Có nền tảng cho cryptographic exclusion nhưng UX chưa hoàn chỉnh, session revoke
không remote-wipe và chi phí vận hành/test quá lớn so với product hiện tại.

## Hệ quả

### Tích cực

- Một recovery path duy nhất và Settings ít khái niệm bảo mật nội bộ.
- Giảm schema, RPC, key store, BLoC và test protocol.
- Server vẫn không có plaintext TOTP hoặc DEK.

### Tiêu cực

- Không còn backup file offline.
- Không xoay key tại chỗ; phải xóa cloud và thiết lập lại.
- Không còn targeted session/device revoke trong ứng dụng.
- Client protocol cũ không tương thích schema mới.

### Rủi ro

- Mất recovery key đồng thời mất mọi thiết bị giữ DEK làm cloud snapshot không
  thể khôi phục. UI phải yêu cầu xác nhận đã lưu key khi setup.
- Thiết bị đã từng giữ DEK không thể bị remote-wipe. Xóa remote chỉ chặn backup
  cloud tương lai, không xóa local vault.

## Bảo mật và quyền riêng tư

Snapshot dùng AES-256-GCM và AAD bind user/revision/version. Recovery key chỉ tồn
tại trong memory lúc tạo/nhập; DEK ở secure storage. RLS và authenticated CAS RPC
vẫn bắt buộc. Không log secret, plaintext snapshot, recovery key hoặc full URI.

## Dữ liệu và compatibility

Local vault v2 không đổi. Remote contract là breaking reset: snapshot cũ và mọi
device/session/wrap row bị xóa khi deploy baseline mới. `.hyauth` v1 không còn
được import/export. Không giữ fallback/dual-write.

## Xác minh

Unit test crypto/model/use case, PostgreSQL RLS/CAS contract, setup/recovery/
conflict widget test, full quality gate và native runtime smoke.

## Rollout

1. Chuẩn bị client mới và cho quality gate pass.
2. Dừng cloud write của client cũ trong maintenance window.
3. Tạo full backup/checksum/off-host copy và restore rehearsal.
4. Deploy baseline tối giản, xác minh RLS/CAS và tạo post-backup.
5. Phát hành client mới; người dùng thiết lập lại cloud và lưu recovery key mới.
