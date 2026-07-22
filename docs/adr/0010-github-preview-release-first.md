# ADR-0010: Ưu tiên GitHub Releases trước app store

- Trạng thái: Chấp nhận
- Ngày: 2026-07-19
- Owner: Hyperz
- Thay thế: Không
- Bị thay thế bởi: Không

## Bối cảnh

Web production đã hoạt động và CI có thể tạo Debian package cùng Windows NSIS
installer, nhưng owner chưa cung cấp Android/Apple/Microsoft signing credential.
Chờ toàn bộ app store gate sẽ trì hoãn việc cho người dùng thử desktop build đã
được kiểm tra. Hai desktop artifact hiện tại chưa có chữ ký phân phối.

## Quyết định

GitHub Releases là kênh phân phối binary công khai ưu tiên cho giai đoạn hiện tại,
không chỉ là bước tạm chờ app store. Cho phép phát hành **pre-release** có
nhãn rõ ràng là **unsigned preview** cho Windows x64 và Linux amd64 khi:

1. tag dạng `vX.Y.Z-preview.N` khớp version trong `pubspec.yaml`;
2. tag trỏ đúng commit có toàn bộ workflow `CI` pass;
3. artifact được tải trực tiếp từ chính CI run của tag;
4. checksum, allowlist filename và denylist debug/config artifact đều pass;
5. release note nêu signing, platform, SMTP và recovery-key limitation.

Android debug APK, Apple compile build và Windows portable CI bundle không được
đưa vào GitHub Release. Android signed APK có thể tham gia kênh này sau khi owner
chốt app-signing key dùng lâu dài, cung cấp keystore và runtime/upgrade gate pass;
việc đó không phụ thuộc Play Store. Nếu sau này mở Play Store và cần cập nhật chéo
hai kênh, phải đưa chính app-signing key này vào Play App Signing rồi mới tách
upload key; không để Play tự sinh app-signing key khác. macOS package tải từ GitHub
vẫn cần Developer ID, hardened runtime,
notarization và device test. iOS không phát hành public binary qua GitHub vì vẫn
phụ thuộc cơ chế signing/provisioning và kênh phân phối của Apple.

“Stable” vẫn yêu cầu release signing, device test, public legal/support metadata
và các gate tương ứng platform. App store được hoãn tới khi owner chủ động mở lại
milestone, không bị loại khỏi roadmap. SMTP cũng được hoãn và không chặn binary
GitHub Preview; release note phải tiếp tục nói rõ email recovery chưa được xác minh
tới mailbox thật.

## Phương án đã cân nhắc

### Chờ app store và mọi signing credential

Trust UX tốt hơn ngay từ bản đầu nhưng không có mốc owner cung cấp credential và
không tận dụng được desktop package đã vượt hosted runtime/package gate.

### Đưa trực tiếp artifact tạm của CI cho người dùng

Không chọn vì artifact hết hạn, URL không ổn định và không tạo release provenance
hay contract cảnh báo/checksum dễ kiểm chứng.

## Hệ quả

### Tích cực

- Người dùng có URL release ổn định và checksum công khai.
- Published binary truy ngược được về tag, commit và successful CI run.
- Store/signing có thể hoàn thiện sau mà không chặn vòng phản hồi desktop đầu tiên.
- Có thể mở rộng cùng GitHub channel sang Android/macOS khi từng platform đủ gate,
  không buộc đồng thời mở app store.

### Tiêu cực

- Windows có thể hiện SmartScreen; Linux không có package-repository signature.
- GitHub Preview không đại diện cho device/runtime coverage của Android và Apple.
- Email recovery có thể chưa tới người dùng cho đến khi SMTP được cấu hình và E2E
  test pass; không được quảng bá delivery là đã hoạt động.

### Rủi ro

- Người dùng có thể hiểu nhầm preview là stable; giảm thiểu bằng pre-release flag,
  tên tag, release note và tài liệu đều ghi `unsigned`.
- CI artifact hết hạn sau 14 ngày; publish harness phải chạy khi artifact còn hạn.

## Bảo mật và quyền riêng tư

Release chỉ nhận asset allowlist và checksum, từ chối env, source map và debug
symbol. Client chỉ chứa public Supabase publishable config; service-role, SMTP và
database credential không được đưa vào artifact hay Actions. Android keystore và
password chỉ được đưa vào encrypted Actions secrets cho trusted tag CI, khôi phục
tạm trên runner rồi xóa ở bước `always()`; không được đưa vào artifact hoặc log.

## Dữ liệu và compatibility

Không đổi local/cloud data contract. Windows giữ storage identity lịch sử theo
ADR-0009; Linux/Windows package transition và data-retention smoke vẫn là CI gate.
Rollback là xóa GitHub pre-release và giữ Web production; thao tác này không xóa
local vault của người dùng đã cài.

## Xác minh

- `scripts/agent/check.sh full` pass tại release commit.
- Workflow `CI` của chính tag pass toàn bộ job.
- `scripts/agent/check_github_preview_assets.sh` xác minh asset và SHA-256.
- GitHub Release public có pre-release flag, đúng năm asset và tải xuống được.

## Cập nhật triển khai — 20-07-2026

Owner đã backup Android app-signing key và cấu hình bốn encrypted Actions secrets.
Contract hiện tại bắt buộc bảy asset cho tag mới: Windows installer/checksum,
Linux package/checksum, signed Android APK/checksum và manifest tổng. Preview 4 đã
pass tag CI, public unauthenticated re-download, checksum/GitHub digest và exact
Android signer fingerprint. Các câu “hai installer”, “năm asset” và Android ở thì
tương lai phía trên là snapshot của quyết định ban đầu; contract runtime hiện tại
nằm trong `docs/DEPLOYMENT.md` và `docs/PROJECT_STATUS.md`.

## Rollout

1. Đưa release harness vào tested commit; workflow thủ công có thể dùng sau khi
   file đã được merge vào default branch.
2. Tạo/push preview tag trên tested commit và chờ tag CI xanh.
3. Chạy workflow thủ công với confirmation bắt buộc; trước khi workflow có trên
   default branch, chạy đúng cùng harness từ trusted maintainer workstation.
4. Xác minh public URL, asset list và checksum sau download.
5. Khi đủ signing/device/legal/support gate, cập nhật contract để mở stable GitHub
   Release cho platform tương ứng. App store là milestone riêng, chỉ mở khi owner
   quyết định.
