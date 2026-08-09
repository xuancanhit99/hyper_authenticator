# Chrome Extension package

`chrome_extension/` chỉ chứa static MV3 shell. Dart output không được commit;
hãy tạo bằng:

```bash
scripts/agent/build_chrome_extension.sh .env
```

Lệnh tạo `build/chrome-extension/unpacked` để Load unpacked trong Chrome và
`build/chrome-extension/hyper-authenticator-<version>-chrome-extension.zip` cùng
file SHA-256 để phát hành Preview. `scripts/agent/verify_chrome_extension_package.sh` fail nếu package
giữ remote executable code, service worker PWA hoặc quyền vượt MVP.

MVP chưa có QR scanner/import hoặc protected QR export. Không phát hành bản
extension public stable/Chrome Web Store trước khi encrypted IndexedDB vault và
session adapter được hoàn tất, test trên clean Chrome profile và privacy/support
URL sẵn sàng. GitHub Preview có thể được owner cho phép ngoại lệ theo từng bản;
release note phải nêu rõ evidence runtime nào còn thiếu.
