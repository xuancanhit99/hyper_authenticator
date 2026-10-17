# Chrome Extension package

`chrome_extension/` chỉ chứa static MV3 shell. Dart output không được commit;
`icons/icon-{16,32,48,128}.png` là bộ icon HyperZ được đóng vào package, còn
Dart output được tạo bằng:

```bash
scripts/agent/rebuild_chrome_extension_for_local_load.sh
```

Lệnh tạo `build/chrome-extension/unpacked` để Load unpacked trong Chrome và
`build/chrome-extension/hyper-authenticator-<version>-chrome-extension.zip` cùng
file SHA-256 để phát hành Preview. `scripts/agent/verify_chrome_extension_package.sh` fail nếu package
giữ remote executable code, service worker PWA hoặc quyền vượt MVP.
Lệnh trên bắt buộc public cloud config trong `.env`; CI dùng builder thấp tầng
`scripts/agent/build_chrome_extension.sh <public-config>`. Sau mỗi lần build,
bấm **Reload** tại `chrome://extensions` để Chrome dùng output mới.

CanvasKit có thể tự yêu cầu một trong hàng trăm fallback glyph từ
`fonts.gstatic.com` dù Roboto đã được bundle. Vì CSP MV3 phải giữ self-only,
`font-fallbacks/sources.lock` pin URL + SHA-256 của đủ catalog Flutter engine
3.44.6: 724 WOFF2 và 144 OFL. Builder tải song song vào cache ignored trong
`.dart_tool`, verify checksum rồi đóng toàn bộ vào package; runtime chỉ đọc path
nội bộ và không nới CSP cho Google Fonts. Verifier reject thiếu/thừa/tamper,
gồm regression `Noto Sans HK 104` từng gây lỗi với glyph CJK.

MVP chưa có QR scanner/import hoặc protected QR export. Không phát hành bản
extension public stable/Chrome Web Store trước khi encrypted IndexedDB vault và
session adapter được hoàn tất, test trên clean Chrome profile và privacy/support
URL sẵn sàng. GitHub Preview có thể được owner cho phép ngoại lệ theo từng bản;
release note phải nêu rõ evidence runtime nào còn thiếu.
