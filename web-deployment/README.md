# Flutter Web production serving

Harness này đóng gói `build/web` vào Nginx non-root đã pin digest mà không gửi
source hoặc `.env` vào Docker build context.

Build artifact và image:

    scripts/agent/build.sh web .env
    web-deployment/build-image.sh hyper-authenticator-web:1.1.0

Khi chạy, truyền cùng `SUPABASE_URL` đã dùng lúc compile để entrypoint tạo CSP:

    docker run --read-only --tmpfs /tmp:size=1m,mode=1777 \
      --cap-drop ALL --security-opt no-new-privileges \
      --env SUPABASE_URL=https://supabase.example.com \
      --publish 127.0.0.1:8080:8080 \
      hyper-authenticator-web:1.1.0

Reverse proxy phía trước chịu trách nhiệm TLS. Image tự thêm HSTS, CSP, header
chống framing/sniffing, camera same-origin, HTML `no-store` và asset revalidation.
Scanner Web hiện dùng `zxing-wasm 3.1.1` được pin bởi `mobile_scanner`; CSP mở
jsDelivr/Fastly cho script/WASM fallback. Flutter engine dùng Noto Sans fallback
từ `fonts.gstatic.com`; cả `connect-src` và `font-src` chỉ mở đúng origin này.
Chạy contract:

    web-deployment/test.sh

Container test dùng filesystem read-only, drop toàn bộ Linux capability, kiểm tra
SPA fallback, cache, CSP, dotfile, query logging và việc image không chứa `.env`.
