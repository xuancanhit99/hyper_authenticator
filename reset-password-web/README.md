# Trang web khôi phục mật khẩu

Thư mục này chứa trang khôi phục mật khẩu Supabase tĩnh, được phục vụ bởi Nginx.

## Trạng thái

Chưa hoàn thiện và chưa thể deploy ở trạng thái committed hiện tại.

- `index.html` load Supabase JavaScript v2 bundle từ jsDelivr.
- `script.js` lắng nghe `PASSWORD_RECOVERY` session và gọi `auth.updateUser`.
- `SUPABASE_URL` và `SUPABASE_ANON_KEY` là hằng trống.
- `compose.yml` truyền build argument.
- `Dockerfile` không khai báo hoặc sử dụng các argument đó.
- Không có file `env-config.js` được generate hoặc load ở runtime.

Không deploy trang này cho đến khi triển khai và test một configuration path hoàn chỉnh.

## Luồng dự kiến

1. Ứng dụng mobile yêu cầu email recovery.
2. Supabase gửi link tới recovery URL được cho phép.
3. Trang nhận và validate recovery session.
4. User nhập và xác nhận mật khẩu mới.
5. Trang gọi `Supabase auth.updateUser`.
6. Trang xóa URL/session state nhạy cảm và hiển thị thông báo hoàn tất an toàn.

## Yêu cầu production

- Chọn trang này hoặc Flutter route `/update-password` làm recovery surface canonical.
- Chỉ inject public Supabase URL và anon key.
- Không bao giờ nhúng service-role key.
- Pin hoặc self-host external script và định nghĩa Content Security Policy.
- Xóa log session và user object.
- Cấu hình chính xác allowed redirect URL theo environment.
- Test link thành công, hết hạn, malformed, replay và cross-environment.
- Thêm kỳ vọng rate limit và abuse control.
- Thêm link privacy, support và incident contact.
- Cấu hình `no-store` cache khi phù hợp cho recovery response.

## Phát triển local

Command Compose hiện tại được chủ ý không mô tả là chạy được. Trước hết hãy triển khai và review configuration injection. Sau đó ghi command local an toàn theo environment và automated browser test tại đây.

Xem:

- [Tích hợp Supabase](../docs/SUPABASE_INTEGRATION.md)
- [Mô hình bảo mật](../docs/SECURITY.md)
- [Hướng dẫn deployment](../docs/DEPLOYMENT.md)
