# Task: Hardening Nginx Proxy Manager production

- Trạng thái: Đang thực hiện
- Bắt đầu: 2026-07-20
- Owner: Hyperz
- Issue hoặc ADR liên quan: production operations hardening

## Mục tiêu

Loại floating update và world-readable credential khỏi reverse proxy production,
đồng thời thêm timing observability tối thiểu để correlation Auth tail latency.

## Ngoài phạm vi

- Không log request header, client IP, query payload hoặc credential.
- Không nâng NPM major production trước backup/canary và owner approval.
- Không đổi Supabase schema, app runtime hoặc local vault.

## Acceptance criteria

- [x] NPM version hiện tại và upstream stable mới nhất được xác định từ runtime và official release.
- [x] Compose, `.env` và NPM application key không còn world-readable.
- [x] Compose pin exact current digest thay cho `latest`.
- [x] Timing config pass `nginx -t`, reload và public health probe.
- [x] Soak lặp lại có request/upstream timing để correlation outlier.
- [x] Dedicated NPM backup và isolated restore rehearsal pass.
- [x] Full repository gate pass.
- [ ] Branch-head CI pass.

## Bằng chứng hiện tại

- Runtime NPM: `2.14.0`, Certbot `5.3.1`, image từng được khai báo bằng `latest`.
- Official stable: `2.15.1`; `2.15.0` đổi Debian Trixie/OpenResty/Certbot và sửa
  security issue, nên đây là upgrade cần canary thay vì recreate trực tiếp.
- `compose.yaml` chứa ba DB password literal và từng mode `0644`; `keys.json`
  từng mode `0644`. Cả compose, `.env`, `keys.json` đã được khóa `0600` mà không restart.
- Auth soak trước observability: 900/900 HTTP 200, p95 292 ms, một max 3.648 ms.
- Correlated repeat: 900/900, p95 289/max 590 ms; NPM/upstream p95 28/25 ms,
  max 244/244 ms, không có non-200. Slowest client request có NPM/upstream 70/67 ms.
- Backup `npm-20260719T184130Z` pass checksum/archive và restore pass bốn core
  table trong exact MariaDB image cô lập không network.

## Đánh giá rủi ro

- Lộ credential: timing log không chứa header/IP/payload; file secret mode `0600`.
- Mất dữ liệu local/cloud: không tác động Flutter vault hoặc Supabase database.
- Migration: NPM 2.15.x có base-image/toolchain update; chưa thực hiện.
- Rollback: exact compose/config backup, `nginx -t` trước reload, không xóa certificate.
- Tác động platform: mọi public domain dùng NPM; vì vậy major upgrade cần chốt riêng.

## Kế hoạch

- [x] Audit runtime image, compose, secret mode và official release notes.
- [x] Sửa permission credential không cần restart.
- [x] Pin exact runtime digest trong compose production.
- [x] Hoàn tất correlated soak sau khi deploy timing config.
- [x] Chuẩn bị backup/restore harness và canary prerequisite cho NPM 2.15.1.
- [ ] Chuyển DB password sang Docker file secrets trong maintenance window.
- [x] Cập nhật canonical docs và full gate.
- [ ] Commit/push và branch-head CI.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| NPM runtime/version probe | `2.14.0`, Certbot `5.3.1`, container không restart | 2026-07-20 |
| Official GitHub release API | Stable mới nhất `v2.15.1`, published 03-06-2026 | 2026-07-20 |
| Permission + config probe | compose, `.env`, `keys.json` mode `0600`; Compose config/Nginx syntax pass | 2026-07-20 |
| Exact image pin | NPM và MariaDB current image ID khớp pinned digest; running container không recreate | 2026-07-20 |
| Timing probe | 3/3 HTTP 200; client max 232 ms, NPM/upstream max 16 ms; exact 8-field JSON allowlist | 2026-07-20 |
| Correlated soak | 900/900 pass; p95 289/max 590 ms; NPM/upstream p95 28/25 ms và max 244/244 ms | 2026-07-20 |
| Dedicated backup | `npm-20260719T184130Z`; checksum/archive pass trước và sau atomic move | 2026-07-20 |
| Isolated restore | Exact MariaDB image, network tắt, authenticated readiness và 4/4 core table pass; 0 temp container còn lại | 2026-07-20 |
| Final public smoke | Auth 100/100 p95 424/max 436 ms; Studio 401; Flutter Web 200; Nginx syntax/container/timer pass | 2026-07-20 |
| `scripts/agent/check.sh full` + secret scan | Pass 186 test, analyzer, docs, operations/platform/migration contract và 150-commit history scan | 2026-07-20 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SECURITY.md`
- [x] `SUPABASE_INTEGRATION.md`
- [x] `DEPLOYMENT.md`
- [ ] ADR — chưa cần; hardening theo contract hiện có

## Bàn giao

Hardening trước upgrade và local full gate đã hoàn tất; còn branch-head CI.
NPM major upgrade và chuyển Docker file secrets vẫn cần owner chốt maintenance window.
