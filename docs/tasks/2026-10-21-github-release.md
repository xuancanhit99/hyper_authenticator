# Task: Merge P1/P2 và Google OAuth, phát hành GitHub Preview

- Trạng thái: Đang triển khai
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

- [ ] Source/secret scan, PR và CI kiểm chứng.
- [ ] Merge vào master và tag đúng commit.
- [ ] Exact-tag CI pass, publish workflow thành công.
- [ ] Public assets/checksums/provenance verify pass.
- [ ] Cập nhật báo cáo và bàn giao link release.

## Bằng chứng hiện tại

Repo public `xuancanhit99/hyper_authenticator`, default branch `master`.
App version `1.1.5+19`; Web Google login có owner acceptance. Android/Windows/
Linux/extension local builds và tests ghi trong các task trước. Full Windows
gate có host/tooling gaps; release sẽ dùng CI Linux/Windows/Apple của đúng tag.

## Đánh giá rủi ro

- Credentials: secret chỉ ở operator/server/CI secrets, không source hoặc package.
- Local/cloud: không đổi schema; vault v3 không downgrade writer v2.
- Release: Android phải khớp signer pin; Windows/Linux unsigned Preview.
- Extension/native: giữ disclosure các runtime acceptance còn thiếu.
- Rollback: có thể draft release lỗi; không rewrite tag đã public hoặc xóa user data.

## Kế hoạch

- [ ] Chốt source, release notes, PR/CI và merge.
- [ ] Tag, CI build, publish, public verify.

## Nhật ký xác minh

Đang thực hiện. Kết quả sẽ được cập nhật sau khi có GitHub run URLs.

## Tác động tài liệu

- [ ] PROJECT_STATUS / DEPLOYMENT / release task và release notes.

## Bàn giao

Đang thực hiện.
