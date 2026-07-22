# Báo cáo lỗ hổng bảo mật

Không gửi TOTP secret, full `otpauth` URI, recovery key, password, session token
hoặc server credential trong GitHub Issue công khai.

Hãy dùng [GitHub private security advisory](https://github.com/xuancanhit99/hyper_authenticator/security/advisories/new)
để báo cáo riêng tư. Cung cấp phiên bản, platform, tác động và bước tái hiện tối
thiểu đã loại bỏ credential. Project sẽ xác nhận và đánh giá trước khi công bố.

GitHub Preview `v1.1.0-preview.4` gồm Android APK đã ký và Windows/Linux package
chưa ký. Android signer được pin và public verifier kiểm tra lại signature;
Windows SmartScreen, cảnh báo package chưa ký hoặc yêu cầu cho phép cài APK từ
GitHub/browser không tự nó là vulnerability. Hãy báo cáo nếu signer,
checksum/provenance không khớp hoặc có hành vi bảo mật tái hiện được. Camera,
biometric và secure-storage trên thiết bị Android thật vẫn là gate trước stable.
