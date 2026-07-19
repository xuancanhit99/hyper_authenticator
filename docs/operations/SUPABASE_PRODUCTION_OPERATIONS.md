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
- public Auth và Recovery HTTP boundary;
- verified backup gần nhất chưa quá hạn.

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

Backup dùng least-privilege transactional dump, loại raw MariaDB volume/log, lưu
compose/app/Let’s Encrypt cùng exact image và database name metadata, rồi checksum
trước/sau atomic move. Rehearsal chạy exact MariaDB image với `--network none`,
authenticated readiness và bốn core-table probe. Directory/file phải 0700/0600;
không copy artifact này vào repository hoặc CI.

Baseline 19-07-2026: NPM `2.14.0` và MariaDB `10.5.29` pin exact digest;
`npm-20260719T184130Z` pass backup và isolated restore. NPM `2.15.1` vẫn cần owner
duyệt maintenance/canary vì thay base image, OpenResty và Certbot cho mọi domain.

## Contract sau deploy/upgrade

Chạy theo thứ tự:

    scripts/supabase/test_remote_encrypted_vault_contract.sh \
      /path/to/server.env https://api.example.com

    scripts/supabase/test_remote_device_registry_contract.sh \
      /path/to/server.env https://api.example.com

    scripts/supabase/test_remote_recovery_contract.sh \
      /path/to/server.env https://api.example.com \
      https://auth.example.com/reset-password/

    scripts/supabase/test_remote_studio_proxy.sh https://studio.example.com

Sau test xác nhận isolated user được dọn. Không chạy plaintext RLS contract trên
production mới nếu compatibility table đã được freeze/drop.

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
- Thiết bị/session nghi bị lộ: từ thiết bị tin cậy xoay vault key, sau đó dùng
  “Thiết bị đã đăng nhập” để thu hồi target đã register hoặc “Đăng xuất các phiên
  khác” cho phiên cũ/không nhận diện; xác minh remote device/session contract.
  Targeted revoke không remote-wipe local vault và không phải permanent ban.
- Suspected server secret leak: rotate server credential/JWT/SMTP/DB theo scope;
  publishable key xử lý riêng, tuyệt đối không đưa service-role vào app.
- Suspected recovery key/TOTP leak: đây là user credential incident; rotate TOTP tại
  từng service, tạo vault/recovery plan mới sau threat review.

## Khoảng trống

- Chưa có external alert delivery.
- Chưa có PITR/continuous WAL archive.
- Off-host copy chưa ở dedicated backup system.
