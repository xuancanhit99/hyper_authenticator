# Nguồn và phạm vi snapshot

- Upstream: [Next Level Builder — UI UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill).
- License: MIT, giữ nguyên copyright trong [LICENSE](LICENSE).
- License đã đối chiếu với [upstream tại commit `56ea9cf`](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/blob/56ea9cf174ed86786187daa9de0e6247cb0747e4/LICENSE)
  ngày 18-10-2026. Commit này chỉ là mốc kiểm tra license.
- Snapshot skill đã có sẵn trên máy trước khi được đưa vào Git; không có metadata
  xác minh revision cài đặt ban đầu. Script và dữ liệu local khác upstream hiện
  tại, nên không gán toàn bộ snapshot này cho commit kiểm tra license ở trên.
- Điều chỉnh khi đưa vào repository: sửa ví dụ lệnh sang `.agents/skills/`,
  bổ sung license/notice và nhắc tuân thủ theme/security contract của dự án.
- Skill là development tooling, không được bundle vào ứng dụng. Tra cứu dùng
  Python standard library và CSV local; `--persist` mới ghi design-system vào
  output directory do người gọi chọn.
