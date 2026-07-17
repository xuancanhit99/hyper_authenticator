# Task: Triển khai bốn quyết định kiến trúc đã duyệt

- Trạng thái: Hoàn tất batch staged; chưa deploy remote
- Bắt đầu: 2026-07-18
- Owner: canhvx
- ADR: 0003, 0004, 0005, 0006

## Mục tiêu

Chuyển app sang offline-first local vault, chuẩn hóa Web password recovery, dựng
E2EE sync v2 theo rollout an toàn và thêm Apache-2.0.

## Ngoài phạm vi

- Không bật E2EE sync production trước onboarding/export/import recovery key UI.
- Không drop hoặc migrate destructive table plaintext trong batch này.
- Không tự deploy template/migration lên host khi chưa có staging rehearsal.

## Acceptance criteria

- [x] Local vault vào được khi không có Supabase session; app lock vẫn fail closed.
- [x] Logout giữ local vault và biometric preference.
- [x] Flutter recovery request có canonical HTTPS redirect config.
- [x] Self-hosted recovery template dùng one-time token hash trong fragment.
- [x] AES-256-GCM snapshot, AAD, DEK wrapping và recovery-key primitive có test.
- [x] E2EE schema v2 publish atomic theo optimistic revision và owner RLS.
- [x] Apache-2.0 có ở root và được dẫn từ README.
- [x] Full gate, recovery container, migration harness và host build pass.

## Rủi ro và rollback

- Router rollback độc lập data vì local format không đổi.
- Recovery rollback cần rollback cả client redirect, template và allow-list.
- E2EE v2 chỉ additive; table plaintext không bị sửa. Có thể bỏ client/schema v2
  trước khi enable mà không mất dữ liệu hiện tại.
- Recovery key mất đồng nghĩa cloud vault không thể giải mã nếu không còn trusted
  device; UI phải bắt user xác nhận đã lưu key trước enable sync.

## Nhật ký xác minh

| Command | Kết quả |
|---|---|
| Focused router/Auth test | 7 pass |
| Focused crypto/key-store test | 6 pass; encrypted remote mapper thêm 2 pass |
| `reset-password-web/test.sh` | Pass sau khi thêm template |
| `scripts/supabase/test_encrypted_vault_migration.sh` | Pass revision/conflict/RLS |
| `scripts/agent/check.sh full` | Pass docs/generated/format/analyze và 41 test |
| `scripts/agent/build.sh host` | Pass Android debug, Web release và macOS debug |

## Bàn giao

- Offline-first routing, logout boundary, canonical recovery config/template và
  Apache-2.0 đã triển khai trong client/repository.
- Crypto/key-store/encrypted remote boundary và additive migration/RPC đã triển khai
  và test, nhưng SyncBloc/onboarding UI chưa nối nên release sync vẫn khóa.
- Không sửa/drop remote plaintext table và chưa deploy migration/template lên host.
- Bước tiếp theo: recovery-key onboarding/export/import UI, staging deployment,
  PostgREST/Auth E2E và conflict UX trước khi enable E2EE sync.
