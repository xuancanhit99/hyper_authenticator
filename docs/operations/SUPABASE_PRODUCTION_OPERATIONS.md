# Vận hành Supabase production

Tài liệu này mô tả harness version-controlled. URL, key, password, SSH identity và
backup thật nằm ngoài repository. Không chạy operator script với `set -x`.

## Health check

Script: `scripts/supabase/check_production_health.sh`.

Kiểm tra:

- 11 core container running/healthy;
- disk, RAM available và swap;
- encrypted table bật + force RLS;
- active-session helper là `SECURITY DEFINER`; owner SELECT policy và publish RPC
  còn tham chiếu helper/`session_revoked`;
- device registry có FORCE RLS/no direct SELECT, ba RPC security-definer và revoke
  function còn active-session guard + delete đúng `auth.sessions`;
- device key/wrap cùng server-only DEK verifier không cấp direct SELECT; publish-v2,
  wrap và atomic rotation RPC còn `SECURITY DEFINER` đúng signature;
- `public.synced_accounts` không còn trong catalog/PostgREST;
- legacy publish chỉ tạo revision `1`, từ chối expected revision `NULL`;
  publish-v2 có exact-row `FOR UPDATE`, yêu cầu protocol `1` và active device
  binding trước update;
- public Auth và Recovery HTTP boundary;
- verified backup gần nhất chưa quá hạn.

Hai probe plaintext/publish trên thuộc health script mới và chỉ được cài lên
production cùng terminal migrations ngày 22-07-2026; nếu cài trước, health fail là
đúng thiết kế chứ không phải lý do nới contract.

Systemd template:

- `supabase/systemd/hyper-auth-supabase-health.service`;
- `supabase/systemd/hyper-auth-supabase-health.timer`;
- config thật `/etc/hyper-authenticator/supabase-health.env` mode 0640.

Baseline production: timer mỗi 5 phút, service sandbox run pass. Xem log:

    systemctl status hyper-auth-supabase-health.timer
    journalctl -u hyper-auth-supabase-health.service --since today

Không paste journal có credential vào issue.

## Daily local backup

Script: `scripts/supabase/backup_production.sh`.

Một backup gồm:

- `database-full.dump`: custom-format logical dump;
- database globals/roles cần cho restore plan;
- Storage filesystem tar trong thời gian Storage service được quiesce;
- sensitive config tar, loại database volume và Storage duplicate;
- catalog/metadata và `SHA256SUMS`.

Control:

- `flock` chặn hai job đồng thời;
- minimum free disk threshold;
- directory 0700, file 0600;
- `pg_restore --list`, tar listing và checksum validation;
- Storage luôn được start lại trong cleanup trap và phải healthy;
- retention production hiện 7 bản.

Systemd timer chạy hằng ngày lúc 02:30 UTC, có randomized delay 10 phút.

## Restore rehearsal

Script: `scripts/supabase/rehearse_backup_restore.sh BACKUP_DIR`.

Script xác minh checksum/catalog, tạo database tạm ngẫu nhiên trong PostgreSQL
cluster, full restore với `--no-owner --no-privileges`, probe:

- `auth.users` tồn tại;
- `public.encrypted_vault_snapshots` tồn tại;
- table có RLS + FORCE RLS;
- active-session helper/policy/RPC được restore và còn đúng security boundary;
- device-registry table/privilege/RPC được restore đúng security boundary;
- device-wrap table, private verifier và v2/rotation RPC được restore đúng boundary;
- plaintext table đã vắng mặt, legacy publish còn initial-only và v2 definition có
  row lock/protocol `1` guard;
- encrypted và registry table đọc được bằng owner ở database tạm.

Trap luôn force-drop database tạm. Script không restore đè production database.
Nếu process bị kill cứng, kiểm tra và drop database tên `ha_restore_rehearsal_*`
sau khi xác nhận không có session cần giữ.

Baseline 18-07-2026: full restore rehearsal pass với scheduled backup đã checksum,
gồm schema/FORCE RLS/active-session guard.

## Scheduled restore drill

Scripts:

- `scripts/supabase/run_scheduled_restore_drill.sh`;
- `scripts/supabase/check_restore_drill_state.sh`;
- `scripts/supabase/rehearse_backup_restore.sh`.

Systemd timer được trigger hằng ngày lúc 04:30 UTC với randomized delay 15 phút,
nhưng wrapper chỉ restore khi evidence cuối đã ít nhất 7 ngày. Cách này cho phép
lượt fail tự retry vào ngày sau thay vì chờ thêm một tuần. Backup mới nhất phải có
tên canonical, manifest thường, không quá 36 giờ và pass checksum/catalog/full
restore. Rehearsal cùng daily backup dùng chung `flock`; hai job không mutate
cluster đồng thời.

Evidence chỉ được atomic replace sau toàn bộ rehearsal pass:

    /home/xuancanhit/backups/hyper-authenticator/scheduled/.restore-drill/last-success.env

Directory có mode 0700, file 0600. Evidence chỉ chứa format, thời điểm, basename
backup và SHA-256 của manifest; không chứa database data hoặc credential. Health
gate chạy mỗi 5 phút yêu cầu evidence đúng schema, không ở tương lai và chưa quá
9 ngày.

Unit source:

- `supabase/systemd/hyper-auth-supabase-restore-drill.service`;
- `supabase/systemd/hyper-auth-supabase-restore-drill.timer`.

Service có timeout 2 giờ, CPU/IO priority thấp và filesystem sandbox. Triển khai
theo thứ tự: cài checker/runner/rehearsal, chạy một drill thật, sau đó mới cài
health script mới và enable timer. Thứ tự ngược lại sẽ tạo health failure đúng
thiết kế do chưa có evidence.

Kiểm tra:

    systemctl status hyper-auth-supabase-restore-drill.timer
    systemctl show hyper-auth-supabase-restore-drill.service -p Result
    journalctl -u hyper-auth-supabase-restore-drill.service --since today

Rollback automation bằng cách disable timer và khôi phục health/rehearsal script
trước đó. Không xóa backup hoặc evidence khi rollback cho tới khi xác minh xong.

Baseline production 19-07-2026: scheduled runner restore backup
`supabase-20260718T100222Z` pass checksum/catalog/full restore/schema/FORCE RLS/
active-session guard; database tạm được drop, evidence/manifest checksum khớp,
timer và health service đều `success`.

Sau device-registry migration, backup `supabase-20260719T060755Z` và encrypted
off-host copy được tạo; manual full rehearsal pass thêm registry FORCE RLS/no
direct SELECT/three-RPC guard, database tạm được drop và health service vẫn pass.

## Encrypted off-host copy

Script: `scripts/supabase/pull_encrypted_backup.sh`.

Yêu cầu:

- protected operator env có SSH host/port/user/key path;
- remote operator có non-interactive sudo được giới hạn để `find`/`tar` backup
  root 0700; không nới quyền backup directory cho user thường;
- `age` recipient file;
- optional identity file để decrypt-stream verify;
- destination ngoài repository.

Remote tar stream được pipe trực tiếp vào `age`; máy nhận không tạo plaintext tar.
Sau đó tạo SHA-256 sidecar, decrypt-stream tar listing nếu identity được cung cấp,
và giữ 14 encrypted archives.

LaunchAgent template:

`supabase/launchd/com.hyperz.hyper-authenticator.supabase-backup.plist.example`.

Baseline Mac chạy daily 10:15 local + RunAtLoad, last exit code 0. Không dùng Mac
cá nhân làm backup SLA duy nhất; mục tiêu tiếp theo là backup host/object storage độc lập.

## Nginx Proxy Manager

Non-secret timing overlay và exact production pin nằm tại
`supabase/nginx-proxy-manager/`. Timing log chỉ nhận exact Auth health endpoint và
tám field allowlist; không ghi URI, IP, header, User-Agent, payload hoặc credential.
File `_access.log` dùng logrotate mặc định weekly, giữ bốn bản nén.

Trước mọi recreate/upgrade NPM, chạy:

    scripts/supabase/backup_nginx_proxy_manager.sh \
      /opt/stacks/nginx-proxy-manager-app \
      /home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager \
      --allow-nginx-proxy-manager-backup

    scripts/supabase/rehearse_nginx_proxy_manager_backup.sh \
      /path/to/npm-YYYYMMDDTHHMMSSZ \
      --allow-isolated-nginx-proxy-manager-restore

    scripts/supabase/rehearse_nginx_proxy_manager_upgrade.sh \
      /path/to/npm-YYYYMMDDTHHMMSSZ \
      sha256:TARGET_IMAGE_ID \
      TARGET_VERSION \
      --allow-isolated-nginx-proxy-manager-upgrade

    scripts/supabase/test_nginx_proxy_manager_route_matrix.sh \
      /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf \
      /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf \
      --allow-production-nginx-proxy-manager-route-probe

Backup dùng least-privilege transactional dump, loại raw MariaDB volume/log, lưu
compose/app/Let’s Encrypt cùng exact image và database name metadata, rồi checksum
trước/sau atomic move. Rehearsal chạy exact MariaDB image với `--network none`,
authenticated readiness và bốn core-table probe. Directory/file phải 0700/0600;
không copy artifact này vào repository hoặc CI.

Upgrade rehearsal clone app/certificate/database sang internal network, không
publish port và bắt buộc exact version + API 200 + `nginx -t` + 4/4 core table.
Nó xóa cả anonymous volume khi cleanup; image target có thể giữ lại để pin exact
digest nhưng không được coi là production deployment.

Route matrix tự khám phá enabled proxy/redirection/dead-host domain, bắt buộc 0
stream và không log hostname/URL. Critical manifest khóa exact status. Exception
manifest chỉ được chứa exact pre-existing 5xx + 12 ký tự SHA-256 hostname đã audit;
status khác, route mới, domain bị xóa hoặc 000 đều fail. Exception không chứng minh
upstream healthy và phải bị xóa khi route được khôi phục/disable.

Sinh maintenance bundle mà không thay production:

    scripts/supabase/prepare_nginx_proxy_manager_upgrade.sh \
      /opt/stacks/nginx-proxy-manager-app \
      /home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager \
      /path/to/PRODUCTION_PIN \
      /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf \
      /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf \
      --allow-nginx-proxy-manager-upgrade-preparation

Preparation lock route baseline, tạo fresh backup, chạy isolated restore/canary,
probe route lại, rồi render original/candidate Compose. Resolved config được
normalized-compare để chứng minh candidate chỉ đổi exact image. Script không chạy
Compose lifecycle command hoặc thay `compose.yaml`; bundle sensitive giữ 0700/0600.

Deploy bundle sau khi owner duyệt maintenance:

    scripts/supabase/deploy_nginx_proxy_manager_upgrade.sh \
      /opt/stacks/nginx-proxy-manager-app \
      /home/xuancanhit/backups/hyper-authenticator/nginx-proxy-manager \
      /path/to/maintenance-npm-YYYYMMDDTHHMMSSZ \
      /etc/hyper-authenticator/nginx-proxy-manager-critical-routes.conf \
      /etc/hyper-authenticator/nginx-proxy-manager-route-exceptions.conf \
      --allow-production-nginx-proxy-manager-upgrade

Sau rollout, cài script route matrix vào `/usr/local/lib/hyper-authenticator/`,
cài service/timer cùng tên từ `supabase/systemd/`, chạy `systemd-analyze verify`,
start service một lần rồi enable timer. Xác minh `Result=success`,
`ExecMainStatus=0` và timer có `Trigger` kế tiếp; journal không được in hostname.

Production rollout 20-07-2026: fresh backup `npm-20260719T200634Z`, isolated
restore, exact `2.15.1` canary, route recheck và bundle
`maintenance-npm-20260719T200758Z` checksum pass. Deploy harness nâng riêng NPM
app 2.14.0→2.15.1; exact runtime/Compose digest, API 200, `nginx -t` và 26-domain
route matrix đều pass, MariaDB vẫn `10.5.29`. Rollback Compose 2.14.0 giữ mode
0600 trong stack directory.

Lần deploy đầu tự rollback khi recreate làm lộ một upstream store không còn nối
`proxy-network`; runtime 2.14.0 được khôi phục nhưng route gate vẫn fail đúng vì
outage độc lập còn tồn tại. Network-only Compose override của upstream được
normalized-compare, backup rồi deploy; route trở lại 200. Sau fresh preparation,
lần deploy thứ hai pass. Một exception cũ phục hồi 200 nên baseline hiện còn 10
exact 502 exception; hourly persistent route timer đã enable và lượt đầu pass
26/26, sáu critical, 10/10 exception.

Bốn certificate Let’s Encrypt orphan có 0 proxy/redirect/dead-host reference và
domain NXDOMAIN vẫn renew fail khi NPM startup. Không xóa trực tiếp database hoặc
certificate files. Operator phải dùng NPM API/UI để xóa sau backup nếu domain đã
bỏ, hoặc khôi phục DNS rồi renew nếu còn dùng.

## Terminal P0 migration — **Đã triển khai production**

Hai migration đã pass local PostgreSQL concurrency contract và deploy production
ngày 22-07-2026:

    supabase/migrations/20260722100000_harden_device_wrap_publish.sql
    supabase/migrations/20260722110000_retire_plaintext_synced_accounts.sql

Migration đầu giữ onboarding revision `1`, nhưng mọi update tiếp theo phải đi qua
device-bound v2 RPC; v2 khóa exact snapshot bằng `FOR UPDATE` trước khi kiểm tra
protocol `1`. Migration sau đặt `row_security=off`, lấy `ACCESS EXCLUSIVE` lock và
chỉ drop `public.synced_accounts` trong nhánh đã lock khi table rỗng. Operator
thiếu `BYPASSRLS` hoặc còn row đều fail closed; trường hợp còn row trả
`plaintext_legacy_rows_present`, không xóa row/table và không dùng `CASCADE`.

Trình tự bắt buộc:

1. Chốt maintenance window và dừng rollout client/server khác.
2. Tạo fresh full backup bằng `backup_production.sh`; xác minh manifest/catalog,
   tạo encrypted off-host copy và chạy restore rehearsal trên chính backup đó.
3. Kiểm tra lại ngay trước mutation: encrypted/device state tương thích và
   `select count(*) from public.synced_accounts` bằng `0`. Không in row content.
4. Apply đúng thứ tự với `ON_ERROR_STOP=1`:

       docker exec -i supabase-db \
         psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
         < supabase/migrations/20260722100000_harden_device_wrap_publish.sql

       docker exec -i supabase-db \
         psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
         < supabase/migrations/20260722110000_retire_plaintext_synced_accounts.sql

5. Reload PostgREST schema cache theo lifecycle của stack, rồi chạy health và toàn
   bộ remote contracts bên dưới.
6. Tạo post-change backup và restore rehearsal; chỉ mở lại rollout khi table-absent,
   publish cutoff/row-lock và cleanup test user đều pass.

Evidence lượt deploy: pre-backup/off-host `supabase-20260722T153421Z`; zero-row
preflight; hai migration + PostgREST reload pass. Một post-backup đầu đã tạo đủ
artifact nhưng service báo fail ở retention vì ba archive lịch sử thuộc
`root:root`; ownership được chuẩn hóa về service account, giữ mode private, rồi
service chạy lại thành công. Post-backup `supabase-20260722T155219Z`, full restore,
encrypted off-host copy, health, table-absent, lượt rollout ban đầu encrypted
35/35, registry 25/25 và
recovery 8/8 đều pass. Final app-data audit bằng 0.

Adversarial review sau rollout bổ sung explicit legacy `NULL` guard, đặt DROP ngay
trong existence/lock branch và `row_security=off` để operator thiếu `BYPASSRLS`
fail closed. Canonical SQL được re-apply sau pre-backup/off-host
`supabase-20260722T161217Z`. Remote encrypted 36/36, health, final zero-data/
table-absent/NULL-guard probe, post-backup `supabase-20260722T161534Z`, full restore
và encrypted off-host copy đều pass.

Nếu zero-row preflight hoặc migration fail, dừng rollout và giữ nguyên database để
điều tra/migrate thủ công. Không xóa row để làm gate xanh. Sau khi plaintext table
đã drop, rollback cần restore full backup + config/release tương thích trong
maintenance window; không dựng lại table thủ công hoặc bật lại plaintext client.

## Contract sau deploy/upgrade

Chạy theo thứ tự:

    scripts/supabase/test_remote_contract.sh \
      /path/to/server.env https://api.example.com

    scripts/supabase/test_remote_encrypted_vault_contract.sh \
      /path/to/server.env https://api.example.com

    scripts/supabase/test_remote_device_registry_contract.sh \
      /path/to/server.env https://api.example.com

    scripts/supabase/test_remote_recovery_contract.sh \
      /path/to/server.env https://api.example.com \
      https://auth.example.com/reset-password/

    scripts/supabase/test_remote_studio_proxy.sh https://studio.example.com

`test_remote_contract.sh` là terminal table-absent contract: cả publishable và
service-role request phải nhận HTTP 404 cùng `PGRST205`/`42P01`. Sau các suite tạo
user, xác nhận isolated user/encrypted row đã được dọn.

Encrypted remote suite đã được nâng thành 36 assertion cho expected-revision `NULL`, negative legacy cutoff,
enroll/self-wrap/confirm protocol `1`, v2 publish, session revoke và cross-tenant
isolation. Phải chạy suite này sau rollout; không xem local PostgreSQL contract là
bằng chứng thay thế cho public HTTPS production boundary.

## Upgrade Supabase

1. Đọc official self-hosted Docker update guide/changelog.
2. Chọn exact commit/release pin; không dùng floating `latest`.
3. Diff compose, `.env.example`, image tag, migration và breaking change.
4. Full backup + encrypted off-host copy + restore rehearsal.
5. Rehearse trên staging/clone.
6. Chốt maintenance/rollback window.
7. Apply upgrade, chờ 11 service healthy.
8. Chạy health + remote contracts + low-concurrency smoke.

Low-concurrency smoke phải dùng budget có exit code, không chỉ quan sát thủ công:

    scripts/supabase/test_auth_load_budget.sh .env

Release baseline: 100 request, concurrency 10, 100% HTTP 200, p95 ≤ 1 giây,
max ≤ 2 giây. Đây là regression threshold từ client tới public origin, không phải
SLA. Soak bảo thủ có thể đặt `LOAD_BATCH_INTERVAL_MS=1000` cùng concurrency 1 để
tránh burst; contract test bắt buộc xác minh pacing và input sai phải fail closed.
Soak public health vẫn không thay production-scale workload.

Lượt bounded soak đầu ngày 19-07-2026 đạt 900/900 HTTP 200 trong 1.134 giây,
p95 292 ms nhưng fail strict max vì một request 3.648 ms. Sau khi deploy NPM timing
allowlist, lượt lặp cùng pacing pass 900/900 trong 1.135 giây, p95 289/max 590 ms;
NPM request/upstream p95 28/25 ms, max 244/244 ms và không có non-200. Request
chậm nhất có DNS 3/TCP 88/TLS 200/TTFB 589 ms trong khi NPM/upstream chỉ 70/67 ms.
Giữ timing correlation khi lặp dài hơn; kết quả này chưa thay workload test.
9. Update `supabase/UPSTREAM_PIN` và `PROJECT_STATUS.md` cùng commit.

Rollback phải khôi phục cả compose/image pin, database và Storage/config tương ứng;
không mix database mới với service cũ nếu upstream không bảo đảm compatibility.

## Incident quick response

- Disk/RAM/container: dừng rollout, giữ backup, đọc bounded journal và health output.
- Auth/recovery failure: giữ local vault usable, không bật plaintext sync fallback.
- Revision conflict tăng: không delete encrypted rows; kiểm tra client/server contract.
- Thiết bị/session nghi bị lộ: dùng “Thiết bị đã đăng nhập” để thu hồi target đã
  register hoặc “Đăng xuất các phiên khác” cho phiên cũ/không nhận diện, rồi xác
  minh remote device/session contract. Đây chỉ là auth-session revocation, không
  remote-wipe local vault, không permanent ban và không tự loại device key khỏi
  quyền giải mã. Generic vault-key rotation hiện cấp wrap mới cho mọi active
  device có membership proof hợp lệ; UI chưa có per-device cryptographic exclusion.
  Nếu TOTP/DEK có thể đã lộ, xử lý như credential incident thay vì dựa vào revoke.
- Suspected server secret leak: rotate server credential/JWT/SMTP/DB theo scope;
  publishable key xử lý riêng, tuyệt đối không đưa service-role vào app.
- Suspected recovery key/TOTP leak: đây là user credential incident; rotate TOTP tại
  từng service, tạo vault/recovery plan mới sau threat review.

## Khoảng trống

- Client chưa có per-device cryptographic exclusion; revoke hiện là session-only.
- Chưa có external alert delivery.
- Chưa có PITR/continuous WAL archive.
- Off-host copy chưa ở dedicated backup system.
