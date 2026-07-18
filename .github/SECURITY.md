# Báo cáo lỗ hổng bảo mật

Không gửi TOTP secret, full `otpauth` URI, recovery key, password, session token
hoặc server credential trong GitHub Issue công khai.

Hãy dùng [GitHub private security advisory](https://github.com/xuancanhit99/hyper_authenticator/security/advisories/new)
để báo cáo riêng tư. Cung cấp phiên bản, platform, tác động và bước tái hiện tối
thiểu đã loại bỏ credential. Project sẽ xác nhận và đánh giá trước khi công bố.

GitHub Preview hiện là Windows/Linux binary chưa ký. SmartScreen hoặc package
signature warning không tự nó là vulnerability; chỉ báo cáo nếu checksum/provenance
không khớp hoặc có hành vi bảo mật tái hiện được.
