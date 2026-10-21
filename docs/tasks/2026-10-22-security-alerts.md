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
- [ ] Các incident GitGuardian test fixture được đánh dấu false positive.
- [ ] CodeQL và OSV chạy thành công, kiểm tra các finding nếu có.
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
- GitGuardian dashboard cần OAuth authorization; đang chờ owner xác nhận riêng.

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
- [ ] Chạy security workflow trên PR, xử lý finding và merge.
- [ ] Đóng đúng incidents trong GitGuardian, giữ secret protection hoạt động.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| GitHub Dependabot alert API sau enable | 0 alerts ở lần kiểm tra đầu | 22-10-2026 |
| OSV v2.7.0 `scan source --lockfile=pubspec.lock` | 187 packages, exit 0 | 22-10-2026 |

## Tác động tài liệu

- [ ] `PROJECT_STATUS.md`
- [ ] `SECURITY.md`
- [ ] `TESTING_STRATEGY.md`

## Bàn giao

Đang triển khai. Không có thay đổi ngoài phạm vi trong working tree lúc bắt đầu.
