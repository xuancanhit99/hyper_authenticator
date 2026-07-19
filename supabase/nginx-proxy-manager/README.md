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

`backup_nginx_proxy_manager.sh` và `test_nginx_proxy_manager_route_matrix.sh`
source `nginx_proxy_manager_database.sh`, rồi stream
`npm_database_exec_container.sh` vào database container. Khi cài một trong hai
operator script lên host, phải cài cả hai helper cùng directory và giữ executable
chỉ cho operator/root. Helper hỗ trợ `MYSQL_PASSWORD`, `MARIADB_PASSWORD` và biến
`*_PASSWORD_FILE` mà không chuyển password qua Docker CLI hoặc log.

`PRODUCTION_PIN` ghi exact image/version đang chạy và target upstream đã review;
file này không tự cho phép upgrade. Production Compose phải khớp hai digest runtime
trước khi backup/recreate. Sau rollout, target có thể bằng current để biểu thị chưa
có upgrade kế tiếp được duyệt; preparation harness cố ý từ chối hai giá trị giống
nhau cho tới khi maintainer cập nhật một target mới đã review.

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

Harness chỉ extract app/Let’s Encrypt vào sandbox 0700, tạo DB root/app secret
file 0400, truyền `MARIADB_*_PASSWORD_FILE` và `DB_MYSQL_PASSWORD__FILE`, restore
DB vào anonymous volume tạm rồi nối hai container qua Docker network `--internal`.
Gate yêu cầu không còn plaintext password trong `Config.Env`, đủ secret mount,
API 200, exact version, `nginx -t`, 4/4 core table và không có host port. Cleanup
xóa container kèm volume, network và sandbox cả khi fail.

Canary `2.15.1` image ID/digest `52b2c599…9858bb` đã pass ngày 19-07-2026; exact
image này được deploy production ngày 20-07-2026 sau fresh backup/restore và
public-route regression. Canary vẫn không thay public route hoặc rollback gate cho
upgrade tương lai.

File-secret canary chạy lại ngày 20-07-2026 từ fresh backup
`npm-20260719T211623Z` đã pass exact NPM 2.15.1/MariaDB 10.5.29, API/Nginx/DB 4/4,
internal/no-port và cleanup. Đây chưa phải production credential migration.

Chuẩn bị file-secret bundle mà không recreate production:

    scripts/supabase/prepare_nginx_proxy_manager_file_secrets.sh \
      /opt/stacks/nginx-proxy-manager-app \
      /home/operator/backups/nginx-proxy-manager \
      /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf \
      /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf \
      --allow-nginx-proxy-manager-file-secret-preparation

Sau khi review bundle/evidence và duyệt maintenance, deploy bằng
`deploy_nginx_proxy_manager_file_secrets.sh` với confirmation
`--allow-production-nginx-proxy-manager-file-secrets`. Deploy recreate DB trước
app và tự rollback exact Compose/`.env`/runtime/routes nếu post-gate fail. Bundle,
secret và rollback đều sensitive; không đưa path hoặc nội dung vào issue/CI log.

Preparation production ngày 20-07-2026 đã tạo fresh backup
`npm-20260719T215745Z` và bundle `file-secrets-npm-20260719T215906Z`. Restore 4/4,
exact file-secret canary, checksum/mode/candidate Compose và route matrix 26/26
đều pass; production app/DB vẫn restart count 0. Đây là deploy input đã chuẩn bị,
không phải bằng chứng credential migration đã chạy.

## Route matrix và maintenance bundle

`test_nginx_proxy_manager_route_matrix.sh` tự đọc mọi enabled proxy/redirection/
dead-host domain từ NPM database, từ chối stream/wildcard chưa có coverage và probe
HTTPS. Critical manifest khóa exact status; exception manifest chỉ chứa exact 5xx
cùng 12 ký tự SHA-256 hostname cho route đã degraded từ trước. Script không in
hostname/URL khi fail. Dùng hai file `.example` trong thư mục này làm schema, nhưng
file production phải nằm ngoài repository và mode `0600`:

    scripts/supabase/test_nginx_proxy_manager_route_matrix.sh \
      /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf \
      /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf \
      --allow-production-nginx-proxy-manager-route-probe

Exception không biến 5xx thành healthy; nó chỉ khóa baseline để NPM upgrade không
tạo regression mới. Xóa exception khi upstream đã khôi phục hoặc route đã disable.

Chuẩn bị maintenance mà không thay Compose/container production:

    scripts/supabase/prepare_nginx_proxy_manager_upgrade.sh \
      /opt/stacks/nginx-proxy-manager-app \
      /home/operator/backups/nginx-proxy-manager \
      supabase/nginx-proxy-manager/PRODUCTION_PIN \
      /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf \
      /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf \
      --allow-nginx-proxy-manager-upgrade-preparation

Preparation chạy route matrix, fresh backup, isolated restore và target canary,
sau đó render original/candidate Compose đã checksum. Resolved Compose temp chứa
credential chỉ ở file 0600 rồi bị xóa; maintenance bundle 0700/0600 vẫn là
sensitive artifact. Contract cấm preparation chạy `compose up/stop/restart` hoặc
thay file Compose production.

Deploy bundle đã chuẩn bị:

    scripts/supabase/deploy_nginx_proxy_manager_upgrade.sh \
      /opt/stacks/nginx-proxy-manager-app \
      /home/operator/backups/nginx-proxy-manager \
      /path/to/maintenance-npm-YYYYMMDDTHHMMSSZ \
      /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf \
      /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf \
      --allow-production-nginx-proxy-manager-upgrade

Harness byte-match production Compose với original bundle, xác minh checksum/
backup/exact current-target image và pre-route trước khi swap. Nó chỉ recreate app,
khóa version/image/API/Nginx/full route sau deploy và tự rollback exact Compose/
image nếu fail; không dừng DB hoặc xóa network/volume.

Baseline sau deploy 20-07-2026: NPM `2.15.1`, MariaDB `10.5.29`, 26 discovered
HTTPS domain, sáu critical route pass và 0 stream. 10 route của stack khác đang
dừng trả exact 502 được khóa bằng hash exception; một exception đã xóa sau khi
route phục hồi 200. Fresh backup `npm-20260719T200634Z`, restore/canary/route
recheck và bundle `maintenance-npm-20260719T200758Z` đều pass. Hourly persistent
systemd route timer đã enable; output chỉ ghi status và hash domain.
