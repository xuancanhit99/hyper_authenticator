# Task: Xử lý cảnh báo GitGuardian và bổ sung security scanning

- Trạng thái: Đang triển khai
- Bắt đầu: 2026-10-22
- Owner: Project owner / Codex
- Issue hoặc ADR liên quan: PR #57 và task GitHub release 21-10-2026

## Mục tiêu

Phân loại và đóng đúng GitGuardian false positives đã xác minh; bật dependency
alerts và đưa quét source/dependency vào GitHub Code scanning với phạm vi rõ ràng.

## Ngoài phạm vi

- Không rewrite public history/tag, disable scanner hoặc thêm broad ignore.
- Không merge các PR version-update không liên quan hoặc đổi runtime/vault/schema.

## Acceptance criteria

- [x] Dependabot alerts, malware alerts và security-update PRs enabled.
- [x] Các incident GitGuardian test fixture được đánh dấu false positive.
- [x] CodeQL và OSV chạy thành công, kiểm tra các finding nếu có.
- [ ] Xử lý 8 findings baseline trên master và xác minh lại default branch.
- [ ] Cập nhật tài liệu, merge source cấu hình và ghi evidence.

## Bằng chứng hiện tại

- GitGuardian PR #57 báo 3 occurrences thuộc 2 incidents `38761452`, `38761453`
  trong `test/features/authenticator/account_payload_limits_test.dart` tại commit
  `1c50327`. Fixture là Base32 của public ASCII `foobar` và `12345678`.
  Commit `d5520af` đã sinh giá trị từ readable text; squash source phát hành không
  còn các literal bị báo. PR vẫn đỏ vì GitGuardian quét cả commit cũ trong PR.
- GitHub Secret scanning: 0 open/0 closed; push protection enabled.
- Dependabot trước đó disabled; đã bật ngày 22-10. API trả 0 alerts ở lần kiểm tra
  đầu sau enable, không dùng kết quả này để kết luận mọi ecosystem đã sạch.
- OSV-Scanner v2.7.0 local đã verify SHA-256 upstream và scan 187 packages từ
  `pubspec.lock`, exit 0, không phát hiện vulnerability trong database tại thời điểm scan.
- Owner đã xác nhận OAuth GitGuardian. Dashboard đã đánh dấu incidents `38761452`,
  `38761453` là `Ignored / Not a secret (false positive)`. Một incident cũ
  `35199888` trong `totp_uri_parser_test.dart`, commit `b186781`, cũng là public
  fixture của test reject duplicate secret query; đã đối chiếu và ignore cùng lý do.
  Filter source name `hyper_authenticator` + Assigned/Triggered trả 0 incident mở.
- Đã yêu cầu rerun check PR #57 qua GitHub UI. GitGuardian trả `neutral` với
  message `old checks cannot be re-run`; đây không phải một lần rescan pass.
  Check GitGuardian của PR #58 pass. Không rewrite lịch sử/tag để đổi badge cũ.
- [Security scan PR #58](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39658902219)
  pass 4/4 jobs. API Code scanning xác nhận 4 SARIF analyses không extraction
  error, 0 PR-diff results: CodeQL Actions, JS/TS, Python và OSV. PR-diff result
  không thay thế default-branch baseline.
- [Master baseline](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39660678978)
  chạy thành công nhưng phát hiện 8 medium alerts: #1-#7 là Flutter Action tag
  mutable, #8 là file data gửi trong CDP request của isolated-browser harness.
  Python/OSV không có finding. Đã pin cả 7 call sites vào đúng upstream v2.23.0
  commit `1a44944`; harness tải script qua loopback asset server thay cho gửi
  nội dung file trong CDP, và validate ws protocol/host/port/page path trước connect.
  Không dismiss CodeQL rule hoặc thêm ignore để che findings.

## Đánh giá rủi ro

- Lộ credential: scanner checkout public tracked source, không nhận operator/CI
  secrets hoặc build config; OSV chỉ scan lockfile. Không upload private log.
- Mất dữ liệu local/cloud: không tác động app, dữ liệu hoặc production services.
- Migration: không có.
- Rollback: revert workflow commit; không rewrite release tag.
- Tác động platform: CodeQL không hỗ trợ Dart. Ba job chỉ phân tích GitHub
  Actions, JS/TS và Python; OSV là dependency scan, không phải Dart source audit.
- Failures: OSV fail khi có vulnerability; upstream workflow cũng fail khi scan
  không tạo kết quả. Không nuốt network/scanner errors thành kết luận sạch.

## Kế hoạch

- [x] Kiểm chứng GitGuardian/test diff và cấu hình GitHub hiện tại.
- [x] Bật Dependabot alerts/malware/security updates và scan lockfile local.
- [x] Chạy security workflow trên PR, xử lý finding và merge.
- [x] Đóng đúng incidents trong GitGuardian, giữ secret protection hoạt động.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| GitHub Dependabot alert API sau enable | 0 alerts ở lần kiểm tra đầu | 22-10-2026 |
| OSV v2.7.0 `scan source --lockfile=pubspec.lock` | 187 packages, exit 0 | 22-10-2026 |
| actionlint v1.7.12 + docs gate + diff check | Pass | 22-10-2026 |
| Security scanning [39658902219](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39658902219) | 4/4 pass, SARIF analyses 0 results/error | 22-10-2026 |
| Full CI [39658901436](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39658901436) | 8/8 pass, gồm quality/backend/secrets và tất cả platform jobs | 22-10-2026 |
| GitGuardian incidents 38761452, 38761453, 35199888 | Ignored / Not a secret (false positive), repo filter 0 open | 22-10-2026 |
| Master security baseline 39660678978 | Scan success, 8 medium alerts cần xử lý, không gọi là clean pass | 22-10-2026 |
| `node --test tool/agent/chrome_debug_endpoint_test.mjs` | 2 tests pass; chặn remote endpoint, port mismatch, credentials/query/fragment/path | 22-10-2026 |
| `node tool/agent/extension_vault_concurrency_test.mjs` sau hardening | Real isolated Chrome cold key race/reopen/mutation/tamper/missing/invalid key pass | 22-10-2026 |

[PR #58](https://github.com/xuancanhit99/hyper_authenticator/pull/58) đã squash
merge thành `91e26e7` vào master sau khi CI 8/8 và security 4/4 pass. Merge dùng
`[skip ci]` để không build lại toàn bộ binaries với cùng cấu hình/source đã kiểm
chứng; security workflow được dispatch riêng trên master. Không thay đổi tag
hoặc artifact của release `v1.1.5-preview.1`.

## Tác động tài liệu

- [ ] `PROJECT_STATUS.md`
- [ ] `SECURITY.md`
- [ ] `TESTING_STRATEGY.md`

## Bàn giao

Đang triển khai. Không có thay đổi ngoài phạm vi trong working tree lúc bắt đầu.
