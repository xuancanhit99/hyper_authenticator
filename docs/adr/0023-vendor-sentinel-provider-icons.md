# ADR-0023: Vendor Sentinel provider icon catalog đã pin

- Trạng thái: Chấp nhận
- Ngày: 2026-08-10
- Owner: xuancanhit99
- Thay thế: Không
- Bị thay thế bởi: Không

## Bối cảnh

Repository năm 2025 từng copy 1.046 icon và mapping từ Sentinel Icons nhưng không
giữ source/version/license/NOTICE. ADR-0007 loại bộ này khỏi release. Audit ngày
10-08-2026 xác nhận mapping cũ trùng SHA-256 và toàn bộ 1.046 asset trùng byte với
upstream commit `15dd66a`; owner duyệt khôi phục bản mới có provenance.

## Quyết định

Vendor snapshot `tommycarpi/sentinel-icons` commit
`626fd8d8014168fbd2e39b6ede8c8a9a50dc8432`: 1.076 image mang đuôi `.png`
(1.038 PNG payload, 38 JPEG payload) và 1.201 issuer/alias.
Giữ nguyên mapping upstream, pin checksum từng ảnh cùng MIT License và đăng ký
license vào Flutter LicensePage.

UI tự suy ra logo từ issuer; logo không là persisted field. Resolver dùng asset
local, sửa case theo inventory, có hai override typo được audit và fallback avatar
ký tự nếu không tìm thấy. Không khôi phục picker cũ vì chọn logo từng thay đổi
issuer thay vì một visual preference độc lập.

## Phương án đã cân nhắc

### Chỉ giữ avatar ký tự

Nhẹ và không có trademark surface nhưng khả năng nhận diện account kém hơn. Không
chọn sau khi owner yêu cầu khôi phục.

### Tải logo từ Internet

Giảm bundle size nhưng làm lộ issuer tới dịch vụ ảnh, phụ thuộc network/cache và
mở thêm content/privacy boundary. Không chọn.

### Chỉ vendor một whitelist nhỏ

Giảm kích thước và audit surface nhưng mất độ phủ của catalog đã có. Có thể xem
xét nếu artifact/store limit trở thành blocker; hiện chọn snapshot đầy đủ.

## Hệ quả

### Tích cực

- Account phổ biến được nhận diện nhanh, offline trên mọi platform.
- Source/version/license/integrity có thể tái hiện.
- Không đổi account, vault hoặc sync serialization.

### Tiêu cực

- Tăng khoảng 28,5 MB raw và hơn 1.000 file trong repository/artifact.
- Mỗi lần update phải review asset/mapping/license và regenerate checksum.

### Rủi ro

- Logo do contributor cung cấp có thể thiếu provenance từng file dù repository
  dùng MIT. Giảm thiểu bằng pin, NOTICE, chỉ dùng để nhận diện, review diff và có
  thể xóa logo bị khiếu nại mà không migration data.
- Trademark thuộc chủ sở hữu tương ứng; không dùng logo để ngụ ý tài trợ/chứng thực.

## Bảo mật và quyền riêng tư

Không request mạng, analytics hoặc log issuer. Asset không chứa executable code.
Resolver chỉ đọc issuer đã có local và fallback fail-safe khi catalog lỗi.

## Dữ liệu và compatibility

Không đổi `AuthenticatorAccount`, local vault, RPC hoặc cloud payload. Client cũ
và mới sync cùng data. Rollback chỉ thay presentation.

## Xác minh

- Check source/mapping/license SHA-256 và checksum 1.076 PNG.
- Unit test normalization/alias/fallback và widget test logo/fallback.
- `scripts/agent/check.sh full` cùng build target/extension smoke.

## Rollout

1. Import snapshot, license, source metadata và checksum.
2. Tích hợp resolver local + fallback.
3. Chạy full gate và kiểm tra artifact size/visual trên target.
4. Nếu có license/trademark complaint hoặc startup/render regression, loại catalog
   và quay lại avatar ký tự; không rollback data.
