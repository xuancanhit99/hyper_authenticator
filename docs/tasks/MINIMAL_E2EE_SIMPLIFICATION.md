# Task: Đơn giản hóa backup cloud E2EE

- Trạng thái: Hoàn thành implementation và production backend rollout; chờ merge/client release
- Bắt đầu: 2026-08-02
- Owner: HyperZ
- ADR liên quan: ADR-0019

## Mục tiêu

Giữ trải nghiệm local-first và backup cloud E2EE nhưng chỉ còn một cơ chế khôi
phục bằng recovery key HA1. Loại bỏ backup file portable, device registry,
device-specific HPKE wrap, key rotation và session-security UI để Settings và
remote contract gần với Google Authenticator hơn.

## Ngoài phạm vi

- Không chuyển TOTP secret thành plaintext hoặc server-decryptable data.
- Không xóa local vault copy-on-write, App Lock, Privacy Shield hoặc conflict CAS.
- Không triển khai automatic background sync trong task breaking cleanup này.
- Không deploy migration phá hủy lên production nếu chưa có backup xác minh được.

## Acceptance criteria

- [x] Không còn route, UI, dependency hoặc platform channel của portable backup.
- [x] Không còn device/session registry, per-device wrap hoặc rotation trong client.
- [x] Cloud setup/recovery/manual backup dùng một snapshot, một DEK và một HA1 key.
- [x] Schema Supabase canonical chỉ giữ encrypted snapshot + CAS RPC tối thiểu.
- [x] Settings chỉ giữ entry đăng nhập/đăng xuất tối giản cùng cloud
  setup/recovery/status/manual backup/remove-cloud; không có session/device UI.
- [x] Tài liệu không còn claim active capability đã xóa.
- [x] Full gate và build smoke mục tiêu pass.

## Bằng chứng hiện tại

- Source path: `lib/features/sync`, `lib/features/settings` và migration
  `20260802000000_create_minimal_encrypted_vault.sql`.
- Cách tái hiện: Settings chỉ còn setup/recovery/manual backup/conflict/remove;
  remote contract 21/21 xác minh public RLS/CAS.
- Test hiện có: `test/features/sync`, integration smoke và PostgreSQL local/remote
  contract.
- Production snapshot cũ đã được giữ trong pre-migration full/off-host backup.

## Đánh giá rủi ro

- Lộ credential: không đổi trust boundary AES-256-GCM; server vẫn không có DEK.
- Mất dữ liệu local: không đổi local vault; xóa `.hyauth` làm mất đường restore
  file nên release note phải nói rõ breaking change.
- Mất dữ liệu cloud: schema mới không tương thích protocol cũ và cần remote reset.
- Migration: deploy trong maintenance window sau backup, rồi buộc client cũ ngừng
  cloud write trước khi mở endpoint mới.
- Rollback: rollback source bằng Git; rollback database bằng full backup đã kiểm
  tra checksum. Không giữ compatibility RPC trong schema mới.
- Tác động platform: Android bỏ native document MethodChannel; các platform còn
  lại bỏ file selector/share dependency nếu không còn call site.

## Kế hoạch

- [x] Xóa portable backup và integration liên quan.
- [x] Xóa device/session/rotation code không còn sử dụng.
- [x] Thu gọn encrypted vault use case và storage contract.
- [x] Thay migration history bằng baseline canonical tối giản.
- [x] Làm gọn Settings và cập nhật tài liệu/ADR.
- [x] Chạy full gate, platform compile và production rollout.
- [x] Khóa regression entry đăng nhập/đăng xuất và archive current-tree Linux.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Baseline `scripts/agent/check.sh full` | Pass trước task, 321 Flutter test | 2026-08-02 |
| `scripts/agent/check.sh full` | Pass: 225 Flutter test + backend/release/infra | 2026-08-02 |
| Android/iOS/macOS compile | Android debug, iOS release no-codesign và macOS unsigned pass | 2026-08-02 |
| Pre/post backup restore | Full schema/data/ACL restore pass ở `pre-minimal` và `minimal` | 2026-08-02 |
| Production remote contract | Health pass, Minimal E2EE 21/21, isolated users cleanup verified | 2026-08-02 |
| Production final audit | 0 snapshot/test user/temp DB; legacy object absent; health timer active/success | 2026-08-02 |
| Targeted regression | Cloud auth action 4/4 (gồm 320 px/200% light/dark) và Linux working-tree archive contract pass | 2026-08-02 |
| Android emulator operator | Auth UI giữ local vault + Minimal E2EE runtime pass; isolated user cleanup verified | 2026-08-02 |
| Linux Ubuntu 24.04 operator | current-tree arm64 build + Secret Service + Minimal E2EE runtime pass; isolated user cleanup verified | 2026-08-02 |
| iPhone 16 Pro Ad Hoc | Production `1.1.0 (11)` Distribution build, in-place install và cold-launch pass | 2026-08-02 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] ADR

## Bàn giao

Breaking cleanup đã triển khai cả source/schema và production backend. Local vault
không đổi; client cũ không cloud-compatible. Merge/release client mới là bước
phân phối tiếp theo.
