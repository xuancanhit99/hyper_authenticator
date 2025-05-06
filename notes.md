
flutter clean
flutter pub get
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs



dart run flutter_native_splash:create


flutter pub run flutter_launcher_icons


flutter pub run rename setAppName --value "HyperZ"

flutter pub run rename setAppName --value "HyperZ" --targets ios,android,macos,windows    


Để tải ứng dụng mới của bạn (với tên gói `app.hyperz.authenticator`) lên Google Play Console, hãy làm theo các bước sau:

**Chuẩn bị:**

1.  **Build App Bundle:** Đảm bảo bạn đã chạy `flutter build appbundle` để tạo tệp `build\app\outputs\bundle\release\app-release.aab`.
2.  **Tạo tệp Debug Symbols:** Tạo tệp `.zip` chứa các thư mục ABI (`armeabi-v7a`, `arm64-v8a`, `x86_64`, ...) từ đường dẫn `build\app\intermediates\merged_native_libs\release\mergeReleaseNativeLibs\out\lib\` như đã hướng dẫn. Đặt tên tệp zip là `native-debug-symbols-vX.zip` (X là versionCode hiện tại).

**Các bước trên Google Play Console:**

1.  **Đăng nhập:** Truy cập [https://play.google.com/console/](https://play.google.com/console/) bằng tài khoản nhà phát triển.
2.  **Tạo ứng dụng mới:**
    *   Nhấp **"Tạo ứng dụng" (Create app)**.
    *   Điền Tên ứng dụng, Ngôn ngữ mặc định, chọn "Ứng dụng", chọn "Miễn phí".
    *   Đồng ý với các tuyên bố và nhấp **"Tạo ứng dụng"**.
3.  **Thiết lập ban đầu:**
    *   Hoàn thành các bước thiết lập trên trang tổng quan ứng dụng mới: Truy cập ứng dụng, Quảng cáo, Xếp hạng nội dung, Đối tượng mục tiêu, Ứng dụng tin tức, Theo dõi COVID-19, An toàn dữ liệu (khai báo đúng về quyền Camera và dữ liệu), Ứng dụng chính phủ.
    *   **Thiết lập trang thông tin ứng dụng:** Chọn Danh mục, cung cấp Email liên hệ, nhập Mô tả ngắn, Mô tả đầy đủ, tải lên Biểu tượng, Ảnh nổi bật, Ảnh chụp màn hình, và cung cấp URL Chính sách quyền riêng tư.
4.  **Tạo bản phát hành Thử nghiệm nội bộ:**
    *   Đi đến **Bản phát hành (Release)** -> **Thử nghiệm (Testing)** -> **Thử nghiệm nội bộ (Internal testing)**.
    *   Nhấp **"Tạo bản phát hành mới" (Create new release)**.
5.  **Tải lên App Bundle và Symbols:**
    *   Trong phần **"App bundles"**, **"Tải lên" (Upload)** tệp `app-release.aab`.
    *   Sau khi xử lý xong, tìm tùy chọn **"Tải tệp biểu tượng gỡ lỗi gốc lên"** và tải lên tệp `.zip` debug symbols đã tạo.
6.  **Chi tiết bản phát hành:**
    *   Nhập **Ghi chú phát hành** (mô tả thay đổi).
7.  **Lưu và Triển khai:**
    *   Nhấp **"Lưu" (Save)**, sau đó **"Xem xét bản phát hành" (Review release)**.
    *   Kiểm tra lại và nhấp **"Bắt đầu triển khai cho Thử nghiệm nội bộ" (Start rollout to Internal testing)**.
8.  **Quản lý người thử nghiệm:**
    *   Trong tab **"Người thử nghiệm" (Testers)** của kênh Thử nghiệm nội bộ, tạo/chọn danh sách email người thử nghiệm.
    *   Cung cấp **"Liên kết chọn tham gia" (Opt-in link)** cho họ.

Sau các bước này, ứng dụng mới của bạn sẽ có mặt trên kênh thử nghiệm nội bộ.