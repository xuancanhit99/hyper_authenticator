# Sentinel Icons inventory

Hyper Authenticator phân phối bản snapshot đã pin từ
[`tommycarpi/sentinel-icons`](https://github.com/tommycarpi/sentinel-icons) để
nhận diện trực quan issuer/provider của mã TOTP.

- Commit upstream: xem `SOURCE.json`.
- License upstream: `LICENSE` (MIT), được đăng ký vào Flutter License Page.
- Asset nguyên bản: `assets/logos/authenticators/*.png`.
- Mapping nguyên bản: `assets/data/authenticator_logo_map.json`.
- Local correction: `assets/data/authenticator_logo_overrides.json` chỉ sửa tên
  asset typo trong mapping, không sửa ảnh hoặc persisted account.
- Integrity: `SHA256SUMS` và `scripts/agent/check_provider_logo_catalog.sh`.

Upstream đặt đuôi `.png` cho toàn bộ catalog nhưng 38 file có payload JPEG hợp lệ.
Hyper Authenticator giữ nguyên byte để bảo toàn source checksum; integrity gate từ
chối mọi payload ngoài PNG/JPEG và widget test xác minh Flutter decode được mẫu
JPEG này.

Các logo là trademark/brand mark của chủ sở hữu tương ứng. Việc hiển thị chỉ có
mục đích nhận diện đúng dịch vụ, không thể hiện tài trợ, liên kết hoặc chứng thực.
MIT License của repository upstream không làm thay đổi quyền trademark của từng
chủ sở hữu.

Không cập nhật trực tiếp từ nhánh `main` trong release. Mỗi lần nâng pin phải
review diff icon/mapping, license, contribution provenance, trademark-purpose,
integrity, kích thước artifact và visual smoke trước khi thay `SOURCE.json` cùng
`SHA256SUMS`.
