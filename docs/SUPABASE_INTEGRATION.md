# Tích hợp Supabase

## Client configuration

Flutter chỉ nhận compile-time define:

- `SUPABASE_URL`;
- `SUPABASE_PUBLISHABLE_KEY`;
- `PASSWORD_RECOVERY_URL` (HTTPS, không query/fragment/user-info);
- `ALLOW_INSECURE_PLAINTEXT_SYNC=false`.

`SUPABASE_ANON_KEY` chỉ là fallback compatibility. Không đặt `SERVICE_ROLE_KEY`
trong client `.env` hoặc build system dành cho Flutter.

Client fail closed nếu URL không phải HTTPS origin, key là `sb_secret_*`, legacy
JWT không có role `anon`, recovery URL release bị thiếu hoặc plaintext flag được
bật. `ALLOW_INSECURE_PLAINTEXT_SYNC` chỉ còn là poison/safety sentinel: giá trị
`true` bị từ chối ở mọi build mode, không phải feature flag có thể bật lại bridge.
Error validation không chứa key. Preflight:

    dart run tool/agent/check_release_config.dart .env

    flutter run --dart-define-from-file=.env

`.env` bị ignore và không được khai báo trong `pubspec.yaml`.

## Auth

- Email/password sign-up và sign-in dùng Supabase Auth.
- Logout hiện tại dùng scope `local` và giữ local TOTP vault.
- Settings có action `others` để hủy mọi session khác nhưng giữ session hiện tại.
  RLS/RPC của encrypted vault kiểm tra `auth.sessions`, nên JWT thuộc session đã
  revoke mất quyền vault ngay cả khi JWT chưa tới `exp`.
- Password recovery canonical là `reset-password-web` qua exact HTTPS redirect.
- GoTrue email template phải dùng one-time `token_hash` cho Web recovery.
- Password reset không phục hồi E2EE recovery key.

Remote recovery harness xác minh generate token, verify session, update password,
re-login, token reuse rejection và malformed-token rejection. Nó không chứng minh
SMTP delivery tới mailbox thật.

## Encrypted database contract

Migration nền đã deploy production theo thứ tự:

    supabase/migrations/20260718190000_create_encrypted_vault_snapshots.sql
    supabase/migrations/20260718230000_enforce_active_vault_sessions.sql
    supabase/migrations/20260719070000_create_authenticator_device_registry.sql

Device-wrap base tiếp tục bằng:

    supabase/migrations/20260719150000_add_device_specific_vault_keys.sql
    supabase/migrations/20260719170000_allow_recovery_device_key_replacement.sql

Terminal hardening đã deploy production ngày 22-07-2026:

    supabase/migrations/20260722100000_harden_device_wrap_publish.sql
    supabase/migrations/20260722110000_retire_plaintext_synced_accounts.sql

`encrypted_vault_snapshots` có một row/user, `FORCE RLS`, chỉ grant SELECT cho
authenticated. Insert/update không được grant trực tiếp; client gọi
`publish_encrypted_vault_snapshot`.

RPC behavior hiện tại là:

- lấy owner từ `auth.uid()`, không nhận `user_id` từ client;
- yêu cầu JWT `session_id` còn tồn tại cho cùng user trong `auth.sessions` và chưa
  qua `not_after`; session đã revoke trả `42501`/`session_revoked`;
- legacy `publish_encrypted_vault_snapshot` chỉ nhận expected revision `0` và chỉ
  tạo row revision `1`; row đã tồn tại trả `PT409`/`revision_conflict`;
- mọi update từ revision `1` trở đi phải dùng
  `publish_encrypted_vault_snapshot_v2`;
- v2 yêu cầu expected revision/generation tối thiểu `1`, khóa exact row bằng
  `FOR UPDATE`, rồi mới kiểm tra protocol `1` và active device binding;
- mismatch/no row ở v2 trả `PT409`/`revision_or_generation_conflict`; protocol
  `0` trả `device_key_protocol_required` trước mutation;
- update atomic thành revision N+1 và giữ nguyên exact key generation;
- trả revision và server `updated_at` để client verify.

Recovery-key rotation dùng v2 RPC: client gửi ciphertext revision mới và
`wrapped_key_*` mới trong một transaction, với exact current generation và active
device binding. Không có trạng thái mà revision mới đã commit nhưng wrapped key
vẫn là bản cũ.

Vault-key rotation dùng riêng `rotate_encrypted_vault_device_keys`: snapshot,
recovery-wrapped DEK, generation, membership verifier và exact device-wrap set đổi
atomically. Generic client hiện gửi danh sách exclusion rỗng, nên mọi active device
có membership proof current-generation hợp lệ đều nhận wrap mới. Backend RPC có
khả năng exact exclusion, nhưng UI chưa expose flow này; auth-session revoke không
đồng nghĩa cryptographic exclusion. Client test chứng minh DEK cũ không decrypt
được revision mới.

Encrypted columns có constraint format/cipher/length. RLS là authorization control;
AES-GCM mới là confidentiality control đối với TOTP secret.

## Device registry contract

`authenticator_device_sessions` không cấp direct SELECT/INSERT/UPDATE/DELETE cho
client dù đã bật + force RLS. API chỉ gồm:

- `register_current_authenticator_device`: lấy owner/session từ JWT, nhận
  installation UUID + display name + platform và upsert đúng current session;
- `list_authenticator_device_sessions`: chỉ trả active registered row của current
  user cùng server-derived `is_current`, không trả `session_id`, IP hoặc user agent;
- `revoke_authenticator_device_session`: nhận opaque registration ID, cấm current
  session/cross-tenant target, soft-mark row rồi xóa đúng `auth.sessions` target.

Installation UUID không phải credential và không dùng để group/revoke theo
authorization. Re-login được phép. Session cũ chưa từng register không hiện trong
list và vẫn cần `SignOutScope.others` khi incident response.

## Client runtime flow

`EncryptedVaultRemoteDataSource` download row của current authenticated user và
publish qua RPC. Nó xác minh current user ID vẫn trùng ID use case đã chụp trước
mỗi remote operation. Response revision phải đúng cả envelope revision và
`expected + 1`.

Plaintext datasource, mapper, repository và use case đã bị xóa khỏi source. Không
còn client path để đọc/ghi `synced_accounts`; safety sentinel chặn giá trị `true`
ở mọi build mode.

## Plaintext retirement — **Đã triển khai production**

`20260722110000_retire_plaintext_synced_accounts.sql` là terminal migration cho
`public.synced_accounts`. Migration chạy trong transaction, lấy `ACCESS EXCLUSIVE`
lock rồi đặt `row_security=off` trước khi đếm mà không đọc nội dung credential.
Operator thiếu `BYPASSRLS` fail closed thay vì nhìn thấy count đã bị policy lọc.
Migration trả SQLSTATE `55000` / `plaintext_legacy_rows_present` nếu còn bất kỳ
row nào. Table và row được giữ nguyên sau failure; chỉ table rỗng mới bị drop ngay
trong nhánh đã lock, không dùng `CASCADE`, và re-apply trên fresh instance là idempotent.

Không có auto-migration plaintext → E2EE vì server không có recovery key/DEK để
mã hóa thay người dùng. Production deploy đã dùng fresh backup, encrypted off-host
copy và zero-row preflight ngay trước mutation; post-backup/full restore cũng pass.
Rollback phải restore backup/schema + release tương thích trong maintenance
window; không bật lại plaintext client path.

## Remote contract

Chạy trên server/operator environment có service-role key; không bật shell tracing:

    scripts/supabase/test_remote_encrypted_vault_contract.sh \
      /path/to/supabase/.env https://api.example.com

Contract tạo hai isolated user, hai session cho User A và tự dọn:

- anonymous không SELECT;
- user A không lộ row cho user B;
- payload chỉ có encrypted shape;
- first publish, monotonic revision, stale conflict và atomic ciphertext/wrapped-key
  replacement;
- session cũ đọc được trước revoke; sau `scope=others`, RLS chặn SELECT và RPC trả
  `session_revoked` dù access JWT cũ chưa hết hạn;
- session hiện tại vẫn SELECT/publish bình thường sau revoke;
- user B không update row user A qua RPC.

Suite hiện có 36 assertion: expected revision `NULL` và legacy update bị cutoff, current native device được
enroll/self-wrap/confirm, revision `2` dùng v2 với binding, stale conflict,
session revoke và cross-tenant non-mutation. Production ngày 22-07-2026 đã pass
36/36; suite vẫn phải chạy lại trên public HTTPS sau mỗi deploy/restore liên quan,
vì local migration contract không thay thế remote evidence này.

Targeted registry contract:

    scripts/supabase/test_remote_device_registry_contract.sh \
      /path/to/supabase/.env https://api.example.com

Contract tạo hai user/ba session, kiểm tra no-direct-table/anonymous/cross-tenant,
current marker, self-revoke reject, targeted refresh/JWT revoke và current session
survival rồi xóa cả test user.

Terminal migration có local PostgreSQL 17 contracts:

    scripts/supabase/test_encrypted_vault_migration.sh
    scripts/supabase/test_plaintext_retirement_migration.sh

Contract thứ nhất chứng minh legacy update và v2 protocol `0` bị từ chối,
exact-row `FOR UPDATE` serialize concurrent confirm/publish, còn protocol `1`
tiếp tục publish được. Contract thứ hai dùng concurrent writer để chứng minh
exclusive-lock retirement fail/rollback nguyên vẹn, rồi empty drop và re-apply
idempotent. Production PostgREST đã reload schema cache và cả public/service-role
đều nhận table-absent:

    scripts/supabase/test_remote_contract.sh \
      /path/to/supabase/.env https://api.example.com

Recovery và Studio:

    scripts/supabase/test_remote_recovery_contract.sh \
      /path/to/supabase/.env https://api.example.com \
      https://auth.example.com/reset-password/

    scripts/supabase/test_remote_studio_proxy.sh https://studio.example.com

Baseline production sau P0 ngày 22-07-2026: encrypted **36/36**, registry 25/25,
recovery 8/8 và table-absent contract pass. Sau contract, test user, session,
encrypted/device row đều được cleanup về 0.

Client runtime E2EE Linux dùng protected operator gate:

    scripts/agent/linux_e2ee_operator.sh \
      .env /secure/path/supabase-operator.env \
      --allow-isolated-remote-user

Operator env mode 0600 nằm ngoài repository. Wrapper tạo isolated user, nhưng chỉ
truyền user-level email/password vào Ubuntu/private-keyring client container;
service-role key không đi vào Flutter hoặc GitHub Actions. Runtime production pass
setup revision 1, sync revision 2, recovery, recovery-key rotation revision 3 và
vault-key rotation revision 4. Sau mỗi lượt, admin DELETE + GET 404 pass; DB probe
cuối xác nhận không còn matching test user hoặc encrypted row.

## Self-hosted stack

- Exact upstream pin: `supabase/UPSTREAM_PIN`.
- Overlay proxy/recovery: `supabase/docker-compose.*.yml`.
- Reverse proxy overlay/pin: `supabase/nginx-proxy-manager/`; production NPM
  `2.15.1` và MariaDB `10.5.29` đã pin exact current digest, không còn `latest`/
  floating patch tag. Upgrade 2.14.0→2.15.1 đã pass fresh backup, isolated restore,
  cloned app/database/certificate canary, auto-rollback deployment harness,
  internal API/Nginx và public-route regression.
- NPM route matrix hiện khám phá 26 HTTPS domain và 0 stream; sáu critical route
  pass. 10 pre-existing 502 thuộc upstream stack khác đã dừng được khóa exact bằng
  hash/status exception, không được mô tả là healthy. Hourly persistent systemd
  gate đã enable và lượt production đầu pass 10/10 exception.
- 11 core container phải healthy trước migration/test.

Release regression cho public Auth health dùng publishable key, không tạo user:

    scripts/supabase/test_auth_load_budget.sh .env

Mặc định gate chạy 100 request/concurrency 10, yêu cầu toàn bộ HTTP 200,
p95 ≤ 1.000 ms và max ≤ 2.000 ms. Có thể override `LOAD_TOTAL_REQUESTS`,
`LOAD_CONCURRENCY`, `LOAD_BATCH_INTERVAL_MS`, `LOAD_MAX_P95_MS` và
`LOAD_MAX_SINGLE_MS` cho protected soak. Pacing chỉ sleep giữa batch, được contract
test và mặc định bằng `0` để giữ release regression cũ; không nới budget chỉ để
làm pipeline xanh.

Bounded production soak ngày 19-07-2026 chạy 900 request/concurrency 1, interval
1 giây sau mỗi batch trong 1.134 giây: 900/900 HTTP 200, p95 292 ms nhưng strict
gate fail vì một max 3.648 ms. Baseline 100 request/concurrency 10 ngay sau đó pass
p95 402/max 406 ms. Health/timer/container cùng cửa sổ đều xanh; Nginx Proxy
Manager/Kong access log cũ chưa có duration nên lần đầu chưa đủ bằng chứng quy nguồn.

Timing overlay sau đó đã deploy bằng official NPM `http_top.conf` và
`server_proxy.conf` extension point. Exact Auth health request chỉ ghi status,
request/upstream timing cùng request ID; field allowlist contract và `nginx -t`
pass. Log dùng suffix `_access.log` để vào default weekly rotation/4 bản nén.
Lượt correlated soak sau deploy pass 900/900 trong 1.135 giây, p95 289/max 590 ms;
NPM request/upstream p95 28/25 ms và max 244/244 ms, không có non-200. Request
chậm nhất phía client có DNS 3/TCP 88/TLS 200/TTFB 589 ms nhưng NPM/upstream tại
thời điểm hoàn tất chỉ 70/67 ms, nên phần lớn tail này nằm trước backend Auth.
- Studio public route phải trả 401 khi thiếu Basic Auth.
- Kong/Supavisor bind loopback; reverse proxy nối qua `proxy-network`.

Không suy luận "mới nhất" từ tag marketing. Upgrade theo official self-hosted
Docker commit, diff `.env.example`/compose, backup trước, staging test, migration,
remote contract rồi mới production rollout.

## Backup và operations

Xem `docs/operations/SUPABASE_PRODUCTION_OPERATIONS.md`. Backup production gồm
database full dump, globals, quiesced Storage và config; mỗi bản phải checksum và
restore rehearsal được. Service-role/server env chỉ ở operator host.

Restore drill production được trigger hằng ngày, chỉ chạy khi evidence đã đủ 7
ngày và retry ngày sau nếu fail. Rehearsal dùng database tạm, dùng chung backup
lock và chỉ ghi evidence 0600 sau checksum/catalog/schema/FORCE RLS/session-guard
probe pass. Health gate yêu cầu evidence chưa quá 9 ngày. Baseline 19-07-2026 pass
và cleanup không còn database rehearsal.

## Device-wrap base — **Đã deploy production**

`20260719150000_add_device_specific_vault_keys.sql` additive-only:

- backfill snapshot `key_generation=1`, `device_wrap_version=0`;
- thêm device public-key/binding-hash và current wrap table không cấp direct
  access, bật + force RLS;
- lưu vault membership verifier dẫn xuất từ DEK trong bảng `private` server-only;
  verifier không nằm trong snapshot SELECT hoặc response RPC;
- bind nullable device key vào registry session cùng installation;
- two-phase `begin → publish wrap → target confirm`;
- verifier-gated replacement khi HA1 recovery phát hiện device private key đã mất;
- chặn legacy publish sau khi protocol version 1 được active;
- v2 normal publish yêu cầu exact generation và active device binding;
- rotation atomically thay snapshot, generation, exact survivor wrap set và xóa
  auth session của device bị loại.

Local PostgreSQL 17 contract chứng minh backward compatibility trước activation,
web enrollment reject, wrong binding/cross-session fail, session không biết DEK
verifier không thể self-wrap, target-only confirmation, incomplete wrap set
rollback, surviving wrap generation mới và excluded session mất quyền. Backend
so khớp vault-level verifier; client vẫn phải verify per-device membership proof
và local unwrap bằng current DEK trước confirm/rotation.

Android AVD và iOS Simulator authenticated runtime tạo hai auth session,
installation UUID và X25519 key độc lập ở generation 1. Primary rotate snapshot +
exact two-wrap set; secondary giữ DEK cũ, đọc current-only wrap, verify proof và
tự persist generation 2 sau khi decrypt revision 4. Operator xóa isolated user và
admin API xác minh 404; đây chưa phải physical two-device evidence.

## Terminal publish hardening — **Đã triển khai production**

`20260722100000_harden_device_wrap_publish.sql` đóng hai đường publish còn lại:

- legacy RPC chỉ được tạo revision `1`, không còn update protocol `0`;
- v2 khóa exact snapshot revision/generation bằng `FOR UPDATE` trước khi đọc
  protocol, rồi yêu cầu protocol `1` và active current-device binding.

Migration đã pass local concurrency contract và production apply. Pre-backup/
off-host, zero-row preflight, health, remote 36-check contract, post-backup/full
restore/off-host copy và final zero-data audit đều pass.

## Khoảng trống đã biết

- SMTP mailbox delivery/expired-token E2E chưa có.
- External alert channel chưa cấu hình.
- Device registry production mới thu hồi auth session. Device-specific wrapped
  DEK client/migration/RPC đã deploy và pass focused + local PostgreSQL + remote
  regression + Linux/Android/iOS runtime; generic client rotation cấp wrap mới
  cho mọi active device có membership proof hợp lệ, chưa có UI cryptographic
  exclusion theo từng thiết bị. Còn physical two-device/independent review.
  Remote wipe local vault không nằm trong thiết kế.
