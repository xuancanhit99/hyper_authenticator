# Chính sách quyền riêng tư của Hyper Authenticator

Cập nhật lần cuối: 18 tháng 7 năm 2026

> Lưu ý phát hành: đây là bản nháp bám theo hiện trạng engineering, không phải tư vấn pháp lý. Chủ dự án phải rà soát theo luật, app store, khu vực, cấu hình backend và hành vi sản phẩm của bản phát hành thực tế.

## Phạm vi

Chính sách này mô tả dữ liệu được xử lý bởi ứng dụng client Hyper Authenticator và trang web khôi phục mật khẩu đi kèm.

## Dữ liệu được xử lý

Local authenticator không yêu cầu tài khoản Supabase. Nếu người dùng chọn kết nối
cloud, ứng dụng có thể xử lý:

- địa chỉ email, định danh xác thực và tên hiển thị tùy chọn khi đăng ký, đăng nhập;
- authentication session do Supabase quản lý;
- dữ liệu tài khoản authenticator, gồm issuer, account label, TOTP secret, algorithm, digits và period;
- tùy chọn local như theme, trạng thái biometric lock, email đã ghi nhớ và trạng thái sync;
- camera frame hoặc ảnh được chọn trong khi giải mã QR.

Tùy chọn Remember Me lưu địa chỉ email và trạng thái checkbox. Ứng dụng không chủ ý lưu mật khẩu tài khoản.

## Xử lý và lưu trữ local

Bản ghi tài khoản authenticator được lưu qua FlutterSecureStorage. Tùy chọn không nhạy cảm được lưu qua SharedPreferences.

Camera frame và ảnh QR được chọn chỉ dùng để giải mã dữ liệu tài khoản. Ứng dụng không chủ ý tải chính ảnh đó lên trong luồng này. Dữ liệu tài khoản đã giải mã có thể được tải lên nếu người dùng bật và chạy cloud sync.

Đăng xuất chỉ kết thúc Supabase session và giữ nguyên tài khoản authenticator cùng
app-lock preference. Local vault thuộc installation/OS profile; các Supabase user
đăng nhập trên cùng profile dùng chung vault sau khi mở khóa thiết bị/app.

## Dịch vụ cloud

Ứng dụng dùng Supabase cho:

- đăng ký, đăng nhập, quản lý session và khôi phục mật khẩu;
- lưu bản ghi tài khoản authenticator đã đồng bộ.

Cloud sync plaintext hiện bị khóa mặc định và luôn bị khóa trong release build.
Bridge tương thích chỉ có thể opt-in ở non-release để kiểm tra migration bằng dữ
liệu tổng hợp. Xác thực Supabase không bắt buộc để dùng local vault.

E2EE AES-256-GCM primitives và schema encrypted snapshot đang được triển khai nhưng
chưa bật trong release. Table compatibility plaintext vẫn tồn tại; backend operator
có thể đọc secret nếu dangerous non-release bridge được dùng.

Trang khôi phục mật khẩu riêng tải bản Supabase JavaScript đã pin version và SRI từ
CDN công khai. Trang không lưu session bền vững hoặc log recovery material theo
thiết kế hiện tại. Web là recovery surface đã chọn, nhưng hosting production,
token-hash email template và luồng end-to-end vẫn phải được xác minh trước phát hành.

## Chia sẻ dữ liệu

Dữ liệu được gửi tới Supabase khi cần cho authentication, password recovery hoặc thao tác sync do người dùng kích hoạt. Dự án không chủ ý bán thông tin cá nhân. Các nghĩa vụ công bố khác phụ thuộc hạ tầng production thực tế và phải được chủ dự án rà soát.

## Lưu giữ và xóa

Bản ghi authenticator local được giữ cho đến khi bị xóa trong ứng dụng hoặc bị xóa
bởi hành vi dọn app storage; đăng xuất không xóa các bản ghi này. Bản ghi cloud
được giữ theo cấu hình database và account retention trên Supabase production.
Client hiện chưa cung cấp luồng tự phục vụ để xóa tài khoản hoàn chỉnh.

## Bảo mật

Không phương thức lưu trữ hoặc truyền dữ liệu nào không có rủi ro. RLS migration
và cross-user test đã được triển khai, nhưng RLS không mã hóa dữ liệu trước backend
operator. Trước khi phát hành production, dự án vẫn phải hoàn tất các blocker trong
`docs/SECURITY.md`, gồm hoàn tất onboarding/rollout E2EE, conflict/recovery flow,
backup và incident process.

## Thay đổi và liên hệ

Chính sách này phải được cập nhật khi authentication, analytics, logging, storage, synchronization, hosting hoặc dịch vụ bên thứ ba thay đổi.

Liên hệ dự án: xuancanhit99@gmail.com
