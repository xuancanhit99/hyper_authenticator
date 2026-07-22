# Flutter Web production serving

Harness này đóng gói `build/web` vào Nginx non-root đã pin digest mà không gửi
source hoặc `.env` vào Docker build context.

Build configured artifact, chạy browser runtime smoke rồi mới đóng image:

    scripts/agent/build.sh web .env
    scripts/agent/web_runtime_smoke.sh
    web-deployment/test.sh
    web-deployment/build-image.sh hyper-authenticator-web:1.1.0-<commit> linux/amd64

`web_runtime_smoke.sh` phục vụ chính `build/web` trên loopback và boot bằng
Chrome/Chromium headless với profile cô lập. Gate yêu cầu Flutter engine mount,
semantics local-vault shell (`Mã xác thực`, `Tài khoản`) và không xuất hiện startup
fallback do thiếu public config. Web CI tạo config tổng hợp dùng các origin
`.invalid`, nên không cần hoặc làm lộ credential production. Positive configured
build và negative build thiếu config đã được chạy để xác nhận harness phân biệt
đúng; đây không thay login/camera smoke trên public HTTPS origin.

`scripts/agent/check.sh full` chỉ kiểm tra shell syntax và Node parser của harness
vì không tạo Web artifact. Browser runtime thật chạy trong Web CI sau configured
release build; `web-deployment/test.sh` tiếp tục là serving/image contract riêng.

Đối số thứ hai pin kiến trúc của host chạy container. Production hiện dùng
`linux/amd64`; truyền sai hoặc bỏ đối số khi cross-build trên Apple Silicon có thể
tạo image `linux/arm64` không chạy đúng trên server. Contract test local có thể bỏ
đối số để dùng kiến trúc native.

Khi chạy, truyền cùng `SUPABASE_URL` đã dùng lúc compile để entrypoint tạo CSP:

    docker run --read-only --tmpfs /tmp:size=1m,mode=1777 \
      --cap-drop ALL --security-opt no-new-privileges \
      --env SUPABASE_URL=https://supabase.example.com \
      --publish 127.0.0.1:8080:8080 \
      hyper-authenticator-web:1.1.0

Reverse proxy phía trước chịu trách nhiệm TLS và là lớp duy nhất phát HSTS. Image
tự thêm CSP, header chống framing/sniffing, camera same-origin, HTML `no-store` và
asset revalidation. Không bật HSTS trong container HTTP nội bộ vì sẽ tạo header
trùng khi edge proxy đã cấu hình HSTS.
Scanner Web hiện dùng `zxing-wasm 3.1.1` được pin bởi `mobile_scanner`; CSP mở
jsDelivr/Fastly cho script/WASM fallback. Flutter engine dùng Noto Sans fallback
từ `fonts.gstatic.com`; cả `connect-src` và `font-src` chỉ mở đúng origin này.
Chạy lại serving contract khi đã có configured artifact:

    web-deployment/test.sh

Container test dùng filesystem read-only, drop toàn bộ Linux capability, kiểm tra
SPA fallback, cache, CSP, dotfile, query logging và việc image không chứa `.env`.

## Live rollback drill

`rehearse-production-rollback.sh` chỉ dành cho operator production có quyền Docker.
Nó yêu cầu exact current/previous image cùng SHA-256 `main.dart.js` và confirmation
`RUN_LIVE_WEB_ROLLBACK_DRILL`. Floating tag, image sai architecture, hash trùng/sai
hoặc deployment không ở exact current image đều fail trước mutation.

Flow:

1. Xác minh current container và public HTTPS origin.
2. Boot cả current/previous image trong shadow container read-only, không nối
   reverse proxy.
3. Snapshot `.env` mode 0600 rồi atomic switch duy nhất `WEB_IMAGE` về previous.
4. Chờ live health, exact container/public JS hash, HSTS/CSP/cache và năm SPA route.
5. Atomic switch lại current và chạy cùng verification.
6. Chỉ sau cả hai phase pass mới atomic publish evidence mode 0600.

Nếu bất kỳ bước nào fail sau mutation, EXIT trap khôi phục exact original `.env`,
recreate current image và verify current public hash. Nếu auto-restore cũng không
được xác minh, script exit 2 cùng cảnh báo `CRITICAL`; operator dùng snapshot
`.env.rollback-drill-*` được giữ trong stack directory. `SIGKILL`, host crash hoặc
Docker daemon crash vẫn cần manual recovery từ snapshot.

Ví dụ shape, không dùng hash minh họa làm production input:

    web-deployment/rehearse-production-rollback.sh \
      hyper-authenticator-web:1.1.0-<current-commit> <current-js-sha256> \
      hyper-authenticator-web:1.1.0-<previous-commit> <previous-js-sha256> \
      RUN_LIVE_WEB_ROLLBACK_DRILL

Live drill có thể recreate container hai lần và gây gián đoạn ngắn. Chạy trong
maintenance window; preflight không phải bằng chứng zero downtime.
