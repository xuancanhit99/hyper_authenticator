# Nginx Proxy Manager production overlay

Thư mục này chỉ chứa cấu hình không bí mật dùng cho reverse proxy production.
Database password, certificate private key, NPM application key và SSH credential
không được đưa vào repository.

## Auth health timing

`http_top.conf` và `server_proxy.conf` dùng hai extension point
`/data/nginx/custom/http_top.conf` và `/data/nginx/custom/server_proxy.conf` được
Nginx Proxy Manager hỗ trợ. File đầu định nghĩa map/log format trước khi các proxy
server được parse; file
sau gắn conditional access log vào proxy server vì server-level log không inherit
HTTP-level log. Chúng chỉ ghi timing metadata của exact endpoint
`supabase-api.vnpay.dev/auth/v1/health`; không ghi client IP, query payload,
request header, publishable key, Authorization hoặc User-Agent.

Triển khai từ workstation tin cậy:

1. Backup file đích và legacy `http.conf` nếu tồn tại, giữ backup mode `0600`.
2. Cài hai file mode `0644` vào bind mount NPM `data/nginx/custom/` với nguyên tên.
3. Chạy `nginx -t` trong container; nếu fail, khôi phục backup hoặc xóa file mới.
4. Chỉ sau syntax pass mới chạy `nginx -s reload`.
5. Gọi health endpoint bằng publishable key và xác minh log JSON có
   `request_time` cùng upstream timing nhưng không có credential.

Tên log kết thúc bằng `_access.log` để khớp logrotate mặc định của NPM: weekly,
giữ bốn bản nén và gửi `USR1` cho Nginx sau rotate. Không dùng tên log tùy ý nằm
ngoài pattern rotation.

Rollback: khôi phục exact backup, chạy `nginx -t`, reload rồi giữ timing log để
điều tra. Không restart database hoặc xóa certificate.

## Image pin và credential

Production được phát hiện từng dùng floating `jc21/nginx-proxy-manager:latest`.
Compose phải pin exact digest đã xác minh trước mọi lần recreate. Ba DB password
hiện còn là literal trong compose production, vì vậy compose và `.env` bắt buộc
mode `0600`; `data/app/keys.json` cũng bắt buộc `0600`.

`PRODUCTION_PIN` ghi exact image/version đang chạy và target upstream đã review;
file này không tự cho phép upgrade. Production Compose phải khớp hai digest runtime
trước khi backup/recreate.

Chuyển password sang Docker file secrets và nâng NPM phải có backup database,
`/data`, `/etc/letsencrypt`, canary/config test và public route regression. Không
tự nâng major base image chỉ vì tag `latest` thay đổi.

Backup canonical trước upgrade:

    scripts/supabase/backup_nginx_proxy_manager.sh \
      /opt/stacks/nginx-proxy-manager-app \
      /home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager \
      --allow-nginx-proxy-manager-backup

Harness dùng transactional least-privilege NPM database dump, archive compose/`.env`/NPM app/
Let’s Encrypt, loại raw MariaDB volume và access log, rồi xác minh catalog cùng
SHA-256. Backup chứa credential/certificate nên toàn bộ directory/file giữ
`0700`/`0600`; mặc định giữ bảy bản.

Rehearse database dump mà không chạm production:

    scripts/supabase/rehearse_nginx_proxy_manager_backup.sh \
      /path/to/npm-YYYYMMDDTHHMMSSZ \
      --allow-isolated-nginx-proxy-manager-restore

Harness dùng exact MariaDB image ID đã đóng băng trong metadata, chạy container
`--network none`, chờ authenticated readiness, restore đúng database name trong
metadata và yêu cầu đủ bốn core table. Temp password chỉ đi qua env file 0600;
container và sandbox được cleanup bằng trap.

Baseline production 19-07-2026: backup `npm-20260719T184130Z` pass checksum cả
trước/sau atomic move; restore rehearsal pass `user`, `proxy_host`, `certificate`
và `setting` trong MariaDB cô lập. Đây là rollback evidence, không tự cho phép
nâng NPM `2.15.1`.

Rehearse target upgrade không publish port:

    scripts/supabase/rehearse_nginx_proxy_manager_upgrade.sh \
      /path/to/npm-YYYYMMDDTHHMMSSZ \
      sha256:TARGET_IMAGE_ID \
      2.15.1 \
      --allow-isolated-nginx-proxy-manager-upgrade

Harness chỉ extract app/Let’s Encrypt vào sandbox 0700, restore DB vào anonymous
volume tạm, nối hai container qua Docker network `--internal`, rồi yêu cầu API
200, exact version, `nginx -t`, 4/4 core table và không có host port. Cleanup xóa
container kèm volume, network và sandbox cả khi fail.

Canary `2.15.1` image ID/digest `52b2c599…9858bb` đã pass ngày 19-07-2026 và
production vẫn ở `2.14.0`. Canary giảm rủi ro compatibility nhưng không thay public
route regression, rollback window hoặc owner approval cho production recreate.
