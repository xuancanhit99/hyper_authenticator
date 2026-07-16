# Chính sách quyền riêng tư của Hyper Authenticator

Cập nhật lần cuối: 17 tháng 7 năm 2026

> Lưu ý phát hành: đây là bản nháp bám theo hiện trạng engineering, không phải tư vấn pháp lý. Chủ dự án phải rà soát theo luật, app store, khu vực, cấu hình backend và hành vi sản phẩm của bản phát hành thực tế.

## Phạm vi

Chính sách này mô tả dữ liệu được xử lý bởi ứng dụng client Hyper Authenticator và trang web khôi phục mật khẩu đi kèm.

## Dữ liệu được xử lý

Ứng dụng hiện yêu cầu tài khoản Supabase. Tùy tính năng được sử dụng, ứng dụng xử lý:

- địa chỉ email, định danh xác thực và tên hiển thị tùy chọn khi đăng ký, đăng nhập;
- authentication session do Supabase quản lý;
- dữ liệu tài khoản authenticator, gồm issuer, account label, TOTP secret, algorithm, digits và period;
- tùy chọn local như theme, trạng thái biometric lock, email đã ghi nhớ và trạng thái sync;
- camera frame hoặc ảnh được chọn trong khi giải mã QR.

Tùy chọn Remember Me lưu địa chỉ email và trạng thái checkbox. Ứng dụng không chủ ý lưu mật khẩu tài khoản.

## Xử lý và lưu trữ local

Bản ghi tài khoản authenticator được lưu qua FlutterSecureStorage. Tùy chọn không nhạy cảm được lưu qua SharedPreferences.

Camera frame và ảnh QR được chọn chỉ dùng để giải mã dữ liệu tài khoản. Ứng dụng không chủ ý tải chính ảnh đó lên trong luồng này. Dữ liệu tài khoản đã giải mã có thể được tải lên nếu người dùng bật và chạy cloud sync.

Hiện tại, đăng xuất sẽ xóa namespace secure storage của ứng dụng, bao gồm các tài khoản authenticator local. Đây là vấn đề sản phẩm đã biết và phải được thông báo rõ hoặc thay đổi trước khi phát hành.

## Dịch vụ cloud

Ứng dụng dùng Supabase cho:

- đăng ký, đăng nhập, quản lý session và khôi phục mật khẩu;
- lưu bản ghi tài khoản authenticator đã đồng bộ.

Cloud sync do người dùng điều khiển trong Settings, nhưng xác thực Supabase hiện là bắt buộc để vào ứng dụng.

Quan trọng: luồng sync hiện tại chưa mã hóa đầu cuối TOTP secret ở phía client trước khi upload. Dữ liệu truyền đi được bảo vệ bởi dịch vụ HTTPS đã cấu hình và access control được deploy trên Supabase, nhưng backend operator được cấp quyền hoặc kẻ tấn công chiếm được database có thể đọc secret đã sync.

Trang khôi phục mật khẩu riêng có thể tải Supabase JavaScript client từ CDN công khai. Hosting production và dependency policy của trang này phải được ghi lại trước khi phát hành.

## Chia sẻ dữ liệu

Dữ liệu được gửi tới Supabase khi cần cho authentication, password recovery hoặc thao tác sync do người dùng kích hoạt. Dự án không chủ ý bán thông tin cá nhân. Các nghĩa vụ công bố khác phụ thuộc hạ tầng production thực tế và phải được chủ dự án rà soát.

## Lưu giữ và xóa

Bản ghi authenticator local được giữ cho đến khi bị xóa trong ứng dụng, bị xóa bởi hành vi dọn app storage hoặc bị xóa khi đăng xuất theo implementation hiện tại. Bản ghi cloud được giữ theo cấu hình database và account retention trên Supabase production. Client hiện chưa cung cấp luồng tự phục vụ để xóa tài khoản hoàn chỉnh.

## Bảo mật

Không phương thức lưu trữ hoặc truyền dữ liệu nào không có rủi ro. Trước khi phát hành production, dự án phải hoàn tất các blocker trong `docs/SECURITY.md`, gồm E2EE cho cloud secret, RLS migration đã test, ngữ nghĩa sync an toàn và cơ chế chống mất dữ liệu.

## Thay đổi và liên hệ

Chính sách này phải được cập nhật khi authentication, analytics, logging, storage, synchronization, hosting hoặc dịch vụ bên thứ ba thay đổi.

Liên hệ dự án: xuancanhit99@gmail.com
