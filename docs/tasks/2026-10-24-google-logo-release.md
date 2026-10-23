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

- [ ] PR/full CI và security scan pass, merge master.
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

- [ ] Version metadata/release notes, PR/CI, merge/tag.
- [ ] Build/deploy Web và verify; publish/verify artifacts đúng tag.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Google button login/register + visual render | 2/2 pass, sáng/tối hiển thị đúng | 24-10-2026 |

## Tác động tài liệu

- [ ] PROJECT_STATUS / DEPLOYMENT / task / release notes.

## Bàn giao

Đang triển khai. Working tree sạch lúc bắt đầu, không ghi đè thay đổi ngoài phạm vi.
