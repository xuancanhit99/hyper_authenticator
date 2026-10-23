# Task: Deploy và phát hành logo Google nền trong suốt

- Trạng thái: Đang triển khai
- Bắt đầu: 2026-10-24
- Owner: Project owner / Codex
- Yêu cầu: Deploy Web và phát hành phiên bản mới từ thay đổi icon đã duyệt.

## Mục tiêu

Phát hành GitHub Preview `v1.1.6-preview.1`, app `1.1.6+20`, và deploy Web
production với logo Google nền trong suốt trên Login/Register.

## Ngoài phạm vi

Không thay OAuth provider, vault v3, database schema hoặc merge dependency PRs.

## Acceptance criteria

- [x] PR/full CI và security scan pass, merge master.
- [ ] Exact-tag CI và publisher pass; public assets/provenance verify.
- [ ] Web configured build, shadow serving và production visual/hash smoke pass.
- [ ] Cập nhật tài liệu và bàn giao.

## Bằng chứng hiện tại

Source icon tại `53556c5`, alpha PNG 0..255; widget tests 2/2 và light/dark visual pass.
Windows quick gate có baseline tooling gaps; full gate cần CI Ubuntu.

## Đánh giá rủi ro

- Credential chỉ ở operator/server/CI store; build dùng public client config.
- Không data migration hoặc thay đổi auth/storage; giữ app/install identity.
- Web rollback về image 1.1.5 hiểu vault v3, snapshot compose trước switch.
- Windows/Linux unsigned Preview, Apple chỉ compile. Giữ owner waiver và
  disclosure extension runtime gaps từ kênh Preview trước.

## Kế hoạch

- [x] Version metadata/release notes, PR/CI, merge/tag.
- [ ] Build/deploy Web và verify; publish/verify artifacts đúng tag.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Google button login/register + visual render | 2/2 pass, sáng/tối hiển thị đúng | 24-10-2026 |

[PR #60](https://github.com/xuancanhit99/hyper_authenticator/pull/60) đã merge
master thành `90df288`.
[PR CI](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39998008020)
pass 8/8, [security](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39998008779)
pass 4/4 và GitGuardian pass. Production-configured Web build từ source feature
`cfb7d62` có cùng runtime tree với merge commit. Shadow serving/version/logo
checksum pass; Chrome qua loopback SSH tunnel render Login và logo đúng.
Headless probe trên server timeout `Runtime.evaluate` khi load cao; không gọi
lần đó là pass. Real Chrome và Web CI runtime smoke pass riêng.

## Tác động tài liệu

- [ ] PROJECT_STATUS / DEPLOYMENT / task / release notes.

## Bàn giao

Đang triển khai. Working tree sạch lúc bắt đầu, không ghi đè thay đổi ngoài phạm vi.
