# Task: Deploy và phát hành logo Google nền trong suốt

- Trạng thái: Hoàn thành
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
- [x] Exact-tag CI và publisher pass; public assets/provenance verify.
- [x] Web configured build, shadow serving và production visual/hash smoke pass.
- [x] Cập nhật tài liệu và bàn giao.

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
- [x] Build/deploy Web và verify; publish/verify artifacts đúng tag.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| Google button login/register + visual render | 2/2 pass, sáng/tối hiển thị đúng | 24-10-2026 |
| PR CI / security / GitGuardian | 8/8, 4/4, success | 24-10-2026 |
| Master CodeQL/OSV | 4 analyses 0 results/error | 24-10-2026 |
| Exact-tag CI | 8/8 pass | 24-10-2026 |
| Web shadow/public/checksum/version và Chrome visual | Pass | 24-10-2026 |
| APK/extension exact-tag logo payload | SHA256 khớp source | 24-10-2026 |
| Publisher / independent public verifier | Pass, 9 assets | 24-10-2026 |
| Docs gate / diff check | Pass | 24-10-2026 |

[PR #60](https://github.com/xuancanhit99/hyper_authenticator/pull/60) đã merge
master thành `90df288`.
[PR CI](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39998008020)
pass 8/8, [security](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39998008779)
pass 4/4 và GitGuardian pass. Production-configured Web build từ source feature
`cfb7d62` có cùng runtime tree với merge commit. Shadow serving/version/logo
checksum pass; Chrome qua loopback SSH tunnel render Login và logo đúng.
Headless probe trên server timeout `Runtime.evaluate` khi load cao; không gọi
lần đó là pass. Real Chrome và Web CI runtime smoke pass riêng.

Web đã deploy `1.1.6+20`, image `hyper-authenticator-web:1.1.6-logo-20261024`.
JS SHA256 `712592a60b51bbdd4d5b3f048a9b0091ad05ee59fc8eea55fb02641024448bac`;
logo SHA256 `d1ce9c2af0b10a7333abc99bc706f9a6a199e5b65bf3e3009624f076b8638e6a`.
Shadow/public SPA routes, CSP/no-store/dotfile denial, version và checksum pass;
real Chrome Login/Register visual pass, screenshot tại ignored
`build/release-20261024/production-{login,register}.jpg`.
Private compose rollback snapshot trước deploy giữ image 1.1.5 hiểu vault v3.
Shadow container và loopback SSH tunnel đã cleanup; live container healthy.
Tag `v1.1.6-preview.1` tại `500c4dc` (runtime tree giống merge/feature source).
Master security run `39999552092` pass 4/4, mọi analysis 0 results/error.
Master push CI trùng tag cùng commit được hủy `39999551607` để ưu tiên exact-tag
run `39999551127`; không dùng run bị hủy làm evidence pass.

Local extension unpacked đã rebuild từ tag 1.1.6, package contract pass và
logo/version khớp. Shell wrapper dừng ở bước ZIP do Windows thiếu `zip`; đã
đóng ZIP/checksum local bằng Python, không dùng artifact này cho public release.
Trang `chrome://extensions` bị browser automation URL policy từ chối (chỉ hỗ trợ
HTTP/HTTPS), nên thao tác Reload local extension còn do owner thực hiện.

Exact-tag CI [39999551127](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39999551127)
pass 8/8; APK đã ký, Windows/Linux upgrade/runtime/installers và Apple compile pass.
APK và extension ZIP tải từ đúng tag artifact chứa logo SHA256 khớp source;
extension manifest là 1.1.6.
Publisher [40001618205](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/40001618205)
pass và publish non-draft pre-release đủ 9 assets; internal public verifier pass.
Workflow public verifier độc lập được dispatch riêng tại `40001851396` vì
release tạo bằng GITHUB_TOKEN không tự kích hoạt workflow khác.

## Tác động tài liệu

- [x] PROJECT_STATUS / DEPLOYMENT / task / release notes.

## Bàn giao

Đã deploy Web 1.1.6+20 và publish
[v1.1.6-preview.1](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.6-preview.1)
public ngày 24-10-2026 (Asia/Saigon), đủ 9 assets. Public verifier độc lập
[40001851396](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/40001851396)
pass: anonymous metadata/assets download, provenance, digests/SHA256, signer pin
và package contracts. Không đổi auth/storage/cloud contract hoặc app identity.
File thay đổi: icon/widget, version metadata/product info test, publisher release
notes và docs DEVELOPMENT/PROJECT_STATUS/DEPLOYMENT/task. Không cần migration.
Windows/Linux unsigned Preview; Apple compile-only và native/extension Google
session/physical acceptance gaps giữ nguyên disclosure. Local unpacked extension
mới cần owner Reload thủ công. Working tree sạch lúc bắt đầu; không ghi đè thay
đổi ngoài phạm vi, docs gate/diff check pass, evidence commit đồng bộ master.
