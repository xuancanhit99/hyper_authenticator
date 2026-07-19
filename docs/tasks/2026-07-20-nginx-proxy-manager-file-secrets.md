# Task: Chuyển NPM database credential sang Docker file secrets

- Trạng thái: Prerequisite source và isolated canary đã hoàn tất; chờ deploy harness
- Bắt đầu: 2026-07-20
- Owner: Hyperz
- Issue hoặc ADR liên quan: production operations hardening

## Mục tiêu

Loại ba DB password literal khỏi Nginx Proxy Manager production Compose và `.env`
mà không đổi credential, mất database/certificate hoặc làm backup, route monitoring
và rollback mất khả năng xác thực.

## Ngoài phạm vi

- Không rotate database password trong cùng maintenance.
- Không đổi NPM/MariaDB image, schema, network, volume hoặc certificate.
- Không xóa backup lịch sử chứa rollback credential trong cùng task.

## Acceptance criteria

- [x] NPM `2.15.1` và MariaDB `10.5.29` runtime xác nhận hỗ trợ file-secret env.
- [x] Backup/route harness đọc được plaintext env hoặc `*_PASSWORD_FILE` mà không log.
- [x] Missing/relative/symlink file fail trước database command.
- [x] Read-only production route matrix bằng helper mới pass.
- [x] Isolated clone dùng exact production image + candidate secret contract pass.
- [x] Fresh production backup và full isolated restore rehearsal pass.
- [ ] Candidate/rollback không đổi ngoài environment/secrets và đã checksum.
- [ ] Maintenance recreate đúng app + DB; runtime/API/Nginx/database/route gate pass.
- [ ] Post-migration backup, restore rehearsal và hourly route service pass.
- [ ] `docker inspect` không còn plaintext DB password trong app/DB Config.Env.

## Bằng chứng hiện tại

- Source path: `scripts/supabase/nginx_proxy_manager_database.sh` và
  `scripts/supabase/npm_database_exec_container.sh`.
- Runtime NPM có `/etc/s6-overlay/s6-rc.d/prepare/60-secrets.sh`, hỗ trợ hậu tố
  `__FILE`; official MariaDB entrypoint gọi `file_env` cho `MYSQL_PASSWORD` và
  `MYSQL_ROOT_PASSWORD`.
- Production hiện có hai service, không có Compose secret; ba password env literal.
- Giả định: giữ nguyên hai giá trị password hiện tại trong secret file 0400.

## Đánh giá rủi ro

- Lộ credential: helper không in password; migration candidate/backup là sensitive.
- Mất dữ liệu local: không tác động Flutter local vault.
- Mất dữ liệu cloud: không tác động Supabase; NPM DB phải có fresh restore evidence.
- Migration: cần recreate cả MariaDB và NPM app để plaintext biến mất khỏi Config.Env.
- Rollback: exact Compose/`.env` literal và secret files phải được giữ mode 0600/0400.
- Tác động platform: public HTTPS route có downtime ngắn khi NPM app restart.

## Kế hoạch

- [x] Thêm dual-source database credential helper và contract test.
- [x] Chạy helper qua production route matrix ở chế độ read-only.
- [x] Chuyển isolated canary sang exact file-secret contract.
- [ ] Viết production preparation/deploy/rollback harness.
- [x] Chạy full repository gate.
- [ ] Commit/push và branch CI.
- [ ] Sau merge, chạy preparation rồi xin owner chốt maintenance mutation.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `test_nginx_proxy_manager_database_exec_contract.sh` | Env/file fallback, exit propagation, silent missing credential và symlink reject pass | 2026-07-20 |
| Production route matrix bằng helper mới | 26 domain, 6 critical, 10/10 exact exception, 0 stream; output redacted | 2026-07-20 |
| Fresh backup + isolated restore | `npm-20260719T211623Z`; checksum/archive và 4/4 core table pass | 2026-07-20 |
| Exact file-secret canary | NPM 2.15.1/MariaDB 10.5.29; DB root/app + NPM `__FILE`, API/Nginx/DB 4/4, internal/no-port và cleanup pass | 2026-07-20 |
| `scripts/agent/check.sh full` + secret scan | Pass docs 62 file, generated/format/analyzer/platform, 186 test, operations/release/migration contract; 156-commit history + staged diff không leak | 2026-07-20 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [ ] `SYSTEM_DESIGN.md` — không đổi app architecture
- [ ] `DATA_MODELS.md` — không đổi data model
- [x] `SECURITY.md`
- [ ] `SUPABASE_INTEGRATION.md` — không đổi Supabase contract
- [x] `DEPLOYMENT.md`
- [ ] ADR — chưa cần; credential transport hardening theo upstream contract

## Bàn giao

Source prerequisite hỗ trợ file secrets đã có, backward-compatible với production
hiện tại và exact isolated canary đã pass. Chưa migrate production; bước tiếp theo
phải bổ sung preparation/deploy rollback, chạy full gate và chỉ recreate app/database
trong maintenance đã được owner duyệt.
