# Task: Web release rollback drill có auto-restore

- Trạng thái: Hoàn tất
- Bắt đầu: 2026-07-19
- Owner: Hyperz
- Issue hoặc ADR liên quan: ADR-0010 không đổi; đây là deployment gate

## Mục tiêu

Chứng minh Flutter Web production có thể rollback từ current immutable image về
previous known-good image rồi forward lại current image, với preflight, exact
artifact hash, public HTTPS verification và auto-restore nếu bất kỳ bước nào fail.

## Ngoài phạm vi

- Thay đổi Flutter source, Supabase, E2EE hoặc local vault.
- Camera/QR device test.
- Android/iOS/macOS/Windows/Linux signing.
- Tự động chạy live drill trong CI hoặc theo timer.

## Acceptance criteria

- [x] Chỉ chạy với explicit live confirmation và exact current/previous image.
- [x] Từ chối floating tag, image sai architecture hoặc JS hash không khớp.
- [x] Preflight cả hai image trong shadow container trước khi đổi live state.
- [x] `.env` được snapshot mode 0600 và chỉ đổi `WEB_IMAGE` atomically.
- [x] Rollback image pass container health, route, public TLS/header và exact JS hash.
- [x] Forward current image pass cùng contract.
- [x] Failure sau mutation tự khôi phục original image/env và không ghi success evidence.
- [x] Evidence 0600 chỉ được atomic publish sau rollback + forward pass.
- [x] Production drill hoàn tất với public origin healthy và original image được giữ.

## Bằng chứng hiện tại

- Source path: `web-deployment/docker-compose.production.yml` và manual steps trong
  `docs/DEPLOYMENT.md`.
- Current production: `hyper-authenticator-web:1.1.0-ae1ab36`, amd64, healthy.
- Previous local image: `hyper-authenticator-web:1.1.0-12fce73`, amd64.
- Hai image có `main.dart.js` SHA-256 khác nhau nên rollback có thể quan sát được.
- Giả định: Nginx Proxy Manager route hiện tại tiếp tục trỏ container alias
  `hyper-authenticator-web:8080` trong `proxy-network`.

## Đánh giá rủi ro

- Lộ credential: harness không source/in `.env`; chỉ đọc exact public
  `SUPABASE_URL` và không đưa URL vào evidence/log.
- Mất dữ liệu: Web image stateless; Flutter browser vault nằm phía client và không
  bị container rollout chạm tới.
- Availability: live container bị recreate hai lần; mỗi transition có thể tạo
  gián đoạn ngắn. Preflight shadow và bounded health wait giảm rủi ro.
- Rollback: EXIT trap luôn atomic restore original `.env`, recreate original image
  và verify exact original hash nếu drill chưa commit success.
- Tác động platform: chỉ Flutter Web production origin.

## Kế hoạch

- [x] Audit source/manual rollback và production current/previous images.
- [x] Chốt exact-image/hash, shadow preflight, atomic env và auto-restore contract.
- [x] Implement harness và deterministic success/failure regression.
- [x] Chạy full gate rồi live rollback→forward drill.
- [x] Cập nhật canonical docs, commit/push và xác minh CI.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Production read-only image audit | Current/previous đều amd64, healthy baseline, JS hash khác nhau | 2026-07-19 |
| `test-production-rollback-contract.sh` | Pass confirmation, previous→current và failure auto-restore với fake Docker/curl | 2026-07-19 |
| `scripts/agent/check.sh full` | Pass 51 docs, generated/format/analyze/platform/release/operations, 106 Flutter test và migration | 2026-07-19 |
| Production live drill | Pass current `ae1ab36` → previous `12fce73` → current `ae1ab36` | 2026-07-19 |
| Independent production post-probe | Compose/container current, healthy, exact JS hash, evidence/snapshot 0600 và 5/5 routes | 2026-07-19 |
| CI `29659987672` tại `7a6b333ff8f85b73ffbe06d56e09b8f16588ef46` | Pass 7/7: Quality, Secret, Android, Apple, Web, Linux và Windows | 2026-07-19 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SECURITY.md`
- [x] `DEPLOYMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] `web-deployment/README.md`
- [x] `ROADMAP.md`

## Bàn giao

Harness, live rollback→forward và CI 7/7 đã pass. Production giữ exact current
image; rollback snapshot/evidence được giữ ngoài repository. Không đổi client hoặc
data contract.
