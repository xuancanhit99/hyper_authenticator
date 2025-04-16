# <img src="assets/logos/hyper-logo-green-non-bg-alt.png" alt="Hyper Authenticator Logo" width="30"/> Hyper Authenticator

**Repository:** [https://github.com/xuancanhit99/hyper_authenticator](https://github.com/xuancanhit99/hyper_authenticator) 💻

Một ứng dụng Flutter đa nền tảng cung cấp xác thực hai yếu tố (2FA) dựa trên TOTP (Mật khẩu dùng một lần dựa trên thời gian). Dự án này tập trung vào việc cung cấp trải nghiệm 2FA an toàn 🛡️ trên nhiều nền tảng (📱 Android, 🍎 iOS, 🌐 Web, 🪟 Windows, 🍏 macOS), tận dụng công nghệ sinh trắc học và cung cấp đồng bộ hóa đám mây an toàn tùy chọn ☁️.

## ✨ Tính năng chính
*   **📱 Đa nền tảng:** Được thiết kế để chạy trên Android, iOS, Web, Windows và macOS.
*   **⏱️ Tạo mã TOTP:** Triển khai thuật toán TOTP tiêu chuẩn (RFC 6238) để tạo mã dựa trên thời gian.
*   **➕ Quản lý tài khoản:** Thêm tài khoản dễ dàng thông qua:
    *   📷 Quét mã QR.
    *   ⌨️ Nhập thủ công khóa bí mật.
    *   🖼️ Chọn ảnh mã QR từ thư viện thiết bị.
*   **🔒 Khóa ứng dụng bằng sinh trắc học:** Bảo mật ứng dụng bằng sinh trắc học của thiết bị (vân tay, nhận dạng khuôn mặt) hoặc mã PIN thông qua `local_auth`.
*   **☁️ Đồng bộ hóa đám mây an toàn (Tùy chọn):** Đồng bộ hóa tài khoản giữa các thiết bị bằng backend Supabase. (Mã hóa đầu cuối 🔐 được lên kế hoạch cho triển khai trong tương lai).
*   **👤 Xác thực người dùng:** Tài khoản người dùng tùy chọn thông qua Supabase để bật tính năng đồng bộ hóa.
*   **🎨 Giao diện tùy chỉnh:** Hỗ trợ chế độ Sáng và Tối.
*   **🖼️ Nhận dạng logo dịch vụ:** Hiển thị logo cho nhiều dịch vụ trực tuyến phổ biến.

## 🚀 Bắt đầu

### Yêu cầu
*   Flutter SDK (phiên bản được chỉ định trong `pubspec.yaml`)
*   Thiết lập nền tảng mục tiêu (Android Studio, Xcode, Trình duyệt web, Môi trường desktop Windows/macOS).
*   (Tùy chọn) Tài khoản Supabase để sử dụng tính năng đồng bộ hóa và xác thực người dùng.

### Cài đặt
1.  Clone repository: `git clone https://github.com/xuancanhit99/hyper_authenticator.git`
2.  Di chuyển vào thư mục dự án: `cd hyper_authenticator`
3.  Tạo tệp `.env` từ `.env.example` và điền Supabase URL và Anon Key của bạn nếu bạn dự định sử dụng các tính năng backend.
4.  Cài đặt dependencies: `flutter pub get`

### Chạy ứng dụng
*   Chọn thiết bị/nền tảng mục tiêu của bạn.
*   Chạy ứng dụng: `flutter run`

## 🛠️ Công nghệ sử dụng
*   **Framework:** Flutter (cho UI đa nền tảng)
*   **Ngôn ngữ:** Dart
*   **Kiến trúc:** Clean Architecture
*   **Quản lý trạng thái:** BLoC, Provider (cho Theme)
*   **Dependency Injection:** GetIt, Injectable
*   **Routing:** GoRouter
*   **Backend:** Supabase (Auth, Database/Storage cho Sync)
*   **Lưu trữ cục bộ:** SharedPreferences (cài đặt), FlutterSecureStorage (dữ liệu nhạy cảm như khóa bí mật TOTP)
*   **Xác thực cục bộ:** local_auth (Sinh trắc học/PIN)
*   **Quét/Phân tích QR:** mobile_scanner
*   **Tạo TOTP:** otp (Triển khai RFC 6238)
*   **Chọn ảnh:** image_picker
*   **Mã hóa (Dự kiến cho Sync):** cryptography

## 📄 Giấy phép
MIT License - Copyright (c) 2025 Hyper