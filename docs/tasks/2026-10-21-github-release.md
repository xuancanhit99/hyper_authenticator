# Task: Merge P1/P2 và Google OAuth, phát hành GitHub Preview

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-10-21
- Owner: Project owner / Codex
- Yêu cầu: Owner cho phép merge toàn bộ phần đã làm vào main/master và phát hành GitHub.
- ADR: ADR-0024, ADR-0025

## Mục tiêu

Commit các sửa P1/P2, Google login và tài liệu vào `master`; phát hành
`v1.1.5-preview.1` từ exact-tag CI artifacts theo release workflow hiện tại.

## Ngoài phạm vi

- Không merge các PR Dependabot ngoài đợt thay đổi đã triển khai.
- Không đưa operator credentials, browser profile/logs hay local builds vào Git.

## Acceptance criteria

- [x] Source/secret scan, PR và CI kiểm chứng.
- [x] Merge vào master và tag đúng commit.
- [x] Exact-tag CI pass, publish workflow thành công.
- [x] Public assets/checksums/provenance verify pass.
- [x] Cập nhật báo cáo và bàn giao link release.

## Bằng chứng hiện tại

Repo public `xuancanhit99/hyper_authenticator`, default branch `master`.
App version `1.1.5+19`; Web Google login có owner acceptance. Android/Windows/
Linux/extension local builds và tests ghi trong các task trước. Full Windows
gate có host/tooling gaps; release đã dùng CI Linux/Windows/Apple của đúng tag.

## Đánh giá rủi ro

- Credentials: secret chỉ ở operator/server/CI secrets, không source hoặc package.
- Local/cloud: không đổi schema; vault v3 không downgrade writer v2.
- Release: Android phải khớp signer pin; Windows/Linux unsigned Preview.
- Extension/native: giữ disclosure các runtime acceptance còn thiếu.
- Rollback: có thể draft release lỗi; không rewrite tag đã public hoặc xóa user data.

## Kế hoạch

- [x] Chốt source, release notes, PR/CI và merge.
- [x] Tag, CI build, publish, public verify.

## Nhật ký xác minh

| Kiểm tra | Kết quả |
|---|---|
| Gitleaks 8.30.1 staged + toàn bộ lịch sử | Pass, không credential leak |
| Git diff check / Dart format / docs / publisher contract | Pass |
| Public Base32 fixture regression sau đổi cách biểu diễn | 11 pass |
| PR [#57](https://github.com/xuancanhit99/hyper_authenticator/pull/57) | Squash merged vào master |
| PR CI [39495522362](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39495522362) | 8/8 jobs success |
| Full quality gate trên Ubuntu CI | Pass generated drift, format, analyzer, Flutter tests, backend và release/infra contracts |
| Windows CI | Historical vault upgrade, local-vault runtime, installer install/launch/upgrade/uninstall/data retention pass |
| Linux CI | Historical upgrade, runtime, Debian install/upgrade/remove và distro matrix pass |
| Apple CI | macOS release và iOS Simulator compile pass; không phân phối Apple binary |
| Merge/tag commit | `8bf680bf37212eba1d5f0c1bc87a584e29bf3c7d` |
| Tag | `v1.1.5-preview.1`, app `1.1.5+19` |
| Exact-tag CI [39497379075](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39497379075) | 8/8 jobs success, artifacts dùng cho publisher |
| Publisher [39526492707](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39526492707) | Success; public non-draft pre-release, đúng 9 assets |
| Public verifier [39526579086](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39526579086) | Success; anonymous download, metadata/provenance, GitHub digests, SHA-256, signer pin và package contracts |

GitGuardian báo các chuỗi public Base32 fixtures ở commit đầu feature branch là
generic high-entropy secrets. Đối chiếu cho thấy đó là vector ASCII/RFC công khai,
không credential production. Test cuối sinh cùng giá trị từ văn bản rõ nghĩa;
11 regression tests pass. Squash merge chỉ đưa source cuối vào master. Năm hằng
storage identifier/algorithm công khai của vendor được gitleaks allow theo từng
dòng; không loại bỏ quét toàn thư viện hoặc credential.

Lần PR CI đầu bị hủy do commit fixture mới; lần cuối 8/8 pass. Master push CI
trùng commit được hủy để ưu tiên exact-tag CI; không dùng run bị hủy làm pass.

## Tác động tài liệu

- [x] PROJECT_STATUS / DEPLOYMENT / release task và release notes.

## Bàn giao

[GitHub release v1.1.5-preview.1](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.5-preview.1)
đã public ngày 21-10-2026 với APK Android, Windows x64 installer, Linux amd64
Debian, extension ZIP và checksum (9 assets). Publisher chỉ lấy artifacts từ
exact-tag CI, không upload local working-tree builds. Public verifier được
dispatch riêng vì release tạo bằng GITHUB_TOKEN không tự kích hoạt workflow khác.

Thay đổi tài liệu: `docs/PROJECT_STATUS.md`, `docs/DEPLOYMENT.md` và task này.
Doc follow-up không đổi runtime/data contract. `scripts/agent/check.sh docs`
và `git diff --check` pass. Không có thay đổi ngoài phạm vi bị ghi đè.

Giới hạn: Windows/Linux unsigned Preview; không phân phối Apple binary.
Extension có owner waiver và disclosure runtime gaps. Native/extension Google
session hoàn chỉnh, physical camera/biometric và acceptance dài hạn còn pending.
Không downgrade vault v3 về writer v2. Không merge PR Dependabot ngoài phạm vi.
