# Task: Làm mới Supabase self-hosted cho Hyper Authenticator

- Trạng thái: Hoàn tất
- Bắt đầu: 2026-07-17
- Owner: Repository owner và AI Agent
- Issue hoặc ADR liên quan: Chưa có

## Mục tiêu

Tạo một bản backup legacy đầy đủ và có thể kiểm chứng, sau đó thay instance Supabase self-hosted hiện tại bằng một deployment sạch dựa trên Docker bundle official ổn định mới nhất, sẵn sàng cung cấp Auth và schema có RLS cho Hyper Authenticator.

## Ngoài phạm vi

- Không nhập dữ liệu legacy vào instance mới.
- Không coi cloud sync chứa TOTP secret plaintext là production-ready hoặc E2EE.
- Không mở PostgreSQL, Studio hoặc service nội bộ trực tiếp ra Internet.

## Acceptance criteria

- [x] Database, global roles, Storage object và cấu hình legacy được backup ngoài repository.
- [x] Mỗi artifact backup có checksum và kiểm tra đọc thành công; tài liệu restore không chứa secret.
- [x] Deployment mới dùng Docker bundle official được pin commit, secret/key mới và PostgreSQL 17.
- [x] Các service bắt buộc healthy; API chỉ được công bố qua reverse proxy HTTPS hiện có.
- [x] Schema `synced_accounts`, grant và RLS policy khớp contract Flutter đã ghi nhận.
- [x] Auth, REST, Storage, Realtime và RLS được smoke test; dữ liệu test được dọn sạch.
- [x] Tài liệu canonical và runbook backup/restore phản ánh trạng thái đã xác minh.

## Bằng chứng hiện tại

- Source path: `lib/core/config/app_config.dart`, `lib/features/auth`, `lib/features/sync`, `docs/SUPABASE_INTEGRATION.md`.
- Cách tái hiện: audit read-only qua SSH, `docker compose ps`, health endpoint và truy vấn catalog PostgreSQL.
- Test hiện có: quality gate trong `scripts/agent/check.sh`; chưa có contract test Supabase remote.
- Giả định: host, reverse proxy, DNS, TLS và SMTP hiện tại tiếp tục được sử dụng; mọi credential của stack mới phải được rotate.

## Đánh giá rủi ro

- Lộ credential: backup config và roles chứa secret/hash; lưu ngoài repository, directory mode `0700`, file nhạy cảm mode `0600`, không in nội dung.
- Mất dữ liệu local: không tác động database local của ứng dụng Flutter.
- Mất dữ liệu cloud: rất cao; chỉ clean stack sau khi backup có checksum và kiểm tra đọc thành công.
- Migration: fresh deployment PostgreSQL 17; không migrate dữ liệu legacy vào database mới.
- Rollback: khôi phục từ database dump, global roles, Storage archive và config archive được pin checksum; giữ manifest phiên bản image.
- Tác động platform: Flutter chỉ đổi endpoint/key runtime khi instance mới vượt qua smoke test.

## Kế hoạch

- [x] Ghi inventory, kích thước và phiên bản stack legacy.
- [x] Tạo và kiểm chứng full backup ngoài repository.
- [x] Pin Docker bundle official và sinh toàn bộ secret/key mới.
- [x] Giữ cấu hình public URL, reverse proxy và SMTP cần thiết mà không tái sử dụng auth secret cũ.
- [x] Khởi tạo deployment sạch, schema/RLS và migration contract.
- [x] Smoke test component, security boundary và cleanup dữ liệu test.
- [x] Cập nhật tài liệu canonical và chạy quality gate.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `git status --short --branch` | Working tree sạch; branch local đi trước remote 5 commit | 2026-07-17 |
| `scripts/agent/context.sh` | Thu thập baseline repository thành công | 2026-07-17 |
| Remote read-only audit | Stack cũ healthy nhưng thiếu schema Flutter, backup automation và nhiều component mới | 2026-07-17 |
| `shasum -a 256 -c SHA256SUMS` | Toàn bộ artifact legacy pass checksum | 2026-07-17 |
| `pg_restore --list database-full.dump` | Custom dump catalog đọc thành công | 2026-07-17 |
| Portable restore rehearsal | Pass; 2 Auth user, 4 `api_keys`, 3.342 log, 2 provider key | 2026-07-17 |
| Official self-hosted smoke test qua public HTTPS | 35 pass, 0 fail | 2026-07-17 |
| Official Auth/API key test qua public HTTPS | 43 pass, 0 fail; ES256/JWKS và HS256 compatibility pass | 2026-07-17 |
| `scripts/supabase/test_remote_contract.sh` | 17 pass, 0 fail; anonymous và cross-user CRUD bị chặn | 2026-07-17 |
| Final data audit | Auth user/audit, Storage, Realtime và `synced_accounts` đều 0 | 2026-07-17 |
| `scripts/agent/check.sh full` | Docs/codegen/format/analyze pass; 12 Flutter test pass | 2026-07-17 |
| `scripts/agent/build.sh host` | Android debug, Web release và macOS debug build pass | 2026-07-17 |
| Host disk/log/Docker cleanup | Disk 93% → 67%, khoảng 19,8 GB được giải phóng; 47/47 container vẫn chạy | 2026-07-17 |
| Supabase health sau cleanup | 11 core service healthy; public Auth HTTP 200 | 2026-07-17 |
| SSH key-only verification | Fresh key connection pass; password-only bị từ chối với exit 255 | 2026-07-17 |
| Xóa Vault MTLS POC theo yêu cầu owner | Xóa 3 container, network, image và `/opt/stacks/vault-mtls-poc`; thêm 2,35 GB disk được giải phóng | 2026-07-17 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [x] `privacy_policy.md`
- [x] ADR-0001

## Bàn giao

### Kết quả

- Backup legacy ngoài repository:
  `/Users/canhvx/Backups/hyper_authenticator/supabase-legacy-20260717-193838`.
- Legacy stack/data/config trên server đã bị xóa sau khi backup pass checksum và
  portable rehearsal.
- Deployment mới dùng `self-hosted/v0.7.0`, commit
  `244301c09ddba21aa963ebea09e712ce89b0401a`, PostgreSQL 17.6.1.136 và 11 core
  service healthy.
- Toàn bộ credential/key được rotate; Flutter `.env` local chỉ nhận public
  URL/publishable key mới và giữ mode `0600`.
- Reverse proxy `502` được sửa bằng shared external Docker network; Kong và
  Supavisor vẫn bind loopback.
- Migration fresh-only tạo `synced_accounts` snake_case, force RLS và grant CRUD
  tối thiểu. Flutter mapper đã đổi contract tương ứng.

### Compatibility và rollback

Client build camelCase cũ không tương thích schema mới; rollout cần dùng source
hiện tại. Dữ liệu legacy không được import. Full rollback phải dựng stack cô lập
khớp version legacy; selective restore phải đi qua staging và schema transform theo
`docs/operations/SUPABASE_LEGACY_BACKUP.md`.

### Rủi ro còn lại

- TOTP secret remote vẫn plaintext; chưa E2EE.
- Upload vẫn xóa-rồi-chèn, không atomic/idempotent.
- Password recovery deep link/static surface chưa hoàn thiện.
- Chưa có scheduled encrypted off-host backup/restore rehearsal cho stack mới.
- Disk hiện còn khoảng 24 GB, RAM available khoảng 1,2 GB và swap dùng khoảng
  1,2/2 GB. Cần load-test trước khi bật Logs/Analytics hoặc tăng tải lớn.
- SSH chỉ còn public-key authentication. Fail2ban/UFW chưa cấu hình và vẫn là
  defense-in-depth follow-up.
