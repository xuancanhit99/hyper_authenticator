# Trang web khôi phục mật khẩu

Trang tĩnh này nhận Supabase password-recovery session và cho phép người dùng đặt mật khẩu mới. Nginx phục vụ trang với CSP, `no-store`, không ghi access log và chỉ khởi động sau khi public runtime configuration hợp lệ.

## Cấu hình runtime

Chỉ truyền public client configuration:

```dotenv
SUPABASE_URL=https://supabase.example.com
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

`SUPABASE_ANON_KEY` chỉ là alias tương thích cấu hình cũ. Entrypoint từ chối URL không phải HTTPS origin, key thiếu/không hợp lệ và key có prefix server secret. Không đưa service-role key, database password hoặc user/session token vào environment.

Config được sinh vào `/tmp/reset-password-env.js` khi container khởi động, không được bake vào image. Đây vẫn là public configuration mà browser tải được; authorization phải do Supabase Auth/RLS enforce.

## Chạy local bằng Compose

Tạo `.env` bị Git ignore với hai biến trên, sau đó:

```sh
docker compose up --build
```

Trang chỉ bind `127.0.0.1:8888` theo mặc định. Đổi port bằng
`RESET_PASSWORD_PORT`. Production cần reverse proxy HTTPS và Supabase redirect
allow-list trỏ đúng public URL.

Flutter client phải truyền cùng public URL qua
`PASSWORD_RECOVERY_URL=https://auth.example.com/reset-password/`. File
`email-templates/recovery.html` được đóng gói trong image để Supabase Auth
self-hosted fetch qua URL nội bộ, ví dụ:

```dotenv
GOTRUE_MAILER_TEMPLATES_RECOVERY=http://reset-password-web:8080/email-templates/recovery.html
```

Tên service/port phải khớp Compose network thực tế. Auth fallback sang template
mặc định nếu URL không truy cập được hoặc Go template không hợp lệ, nên deployment
phải kiểm tra email body thật trước khi mở production.

## Contract của recovery link

Trang hỗ trợ hai dạng link:

- **Khuyến nghị:** one-time `token_hash` trong URL fragment, ví dụ `#token_hash=...&type=recovery`. Cấu hình email template Supabase trỏ tới trang này bằng `{{ .TokenHash }}`. Fragment không được gửi tới Nginx/reverse proxy; JavaScript xóa fragment trước khi exchange bằng `verifyOtp`.
- Legacy implicit recovery chứa access/refresh token trong fragment. Dạng này chỉ được giữ để chuyển tiếp tương thích.

Trang chủ ý từ chối callback PKCE `?code=...` được khởi tạo bởi client khác. PKCE verifier nằm trong storage của client đã yêu cầu email; browser recovery không thể dùng verifier do Flutter giữ. Vì vậy không được chỉ đặt `redirectTo` của Flutter PKCE sang trang này. Nếu chọn Web làm recovery surface canonical, email template phải dùng one-time `token_hash` như trên, redirect URL phải được allow-list chính xác và cần E2E test bằng email thật trên environment cô lập.

Không đặt `token_hash`, code hoặc session trong query string. Nếu hạ tầng hiện tại vẫn dùng query, reverse proxy/CDN/WAF phía trước container cũng phải redact hoặc tắt request-URI logging; `access_log off` của Nginx trong image không kiểm soát log ở lớp upstream.

## Dependency và security boundary

- Supabase JS được exact-pin ở `2.110.7` và khóa bằng SHA-384 SRI trong `index.html`.
- CSP chỉ cho script từ chính origin và jsDelivr, chỉ cho `connect-src` tới `SUPABASE_URL` đã validate.
- Recovery response dùng `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, HSTS và các header chống framing/MIME sniffing.
- Nginx access log bị tắt để query/fragment recovery không xuất hiện trong log do ứng dụng kiểm soát.
- Supabase session chỉ giữ trong memory (`persistSession: false`); URL nhạy cảm được xóa sau khi xử lý.
- UI không hiển thị raw Supabase error và JavaScript không log credential, session, user hoặc response.

## Kiểm tra

```sh
./test.sh
```

Script chạy syntax/static gates và, khi Docker daemon khả dụng, build image, kiểm tra invalid config bị từ chối, healthcheck, CSP/no-store và việc image không chứa `.env`.

Trước production vẫn phải test end-to-end bằng dữ liệu tổng hợp cho link thành công, hết hạn, malformed, reused và cross-environment; đồng thời xác minh SMTP/rate-limit/redirect allow-list tại Supabase.
