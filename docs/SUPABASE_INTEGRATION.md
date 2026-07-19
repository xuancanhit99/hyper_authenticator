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
bật. Error validation không chứa key. Preflight:

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

Migration theo thứ tự:

    supabase/migrations/20260718190000_create_encrypted_vault_snapshots.sql
    supabase/migrations/20260718230000_enforce_active_vault_sessions.sql
    supabase/migrations/20260719070000_create_authenticator_device_registry.sql

`encrypted_vault_snapshots` có một row/user, `FORCE RLS`, chỉ grant SELECT cho
authenticated. Insert/update không được grant trực tiếp; client gọi
`publish_encrypted_vault_snapshot`.

RPC behavior:

- lấy owner từ `auth.uid()`, không nhận `user_id` từ client;
- yêu cầu JWT `session_id` còn tồn tại cho cùng user trong `auth.sessions` và chưa
  qua `not_after`; session đã revoke trả `42501`/`session_revoked`;
- expected revision 0 chỉ insert row mới revision 1;
- expected revision N chỉ update khi current revision bằng N;
- update atomic thành N+1;
- mismatch/no row trả SQLSTATE `PT409` với `revision_conflict`;
- trả revision và server `updated_at` để client verify.

Recovery-key rotation dùng cùng RPC: client gửi ciphertext revision mới và
`wrapped_key_*` mới trong một transaction. Không có trạng thái mà revision mới đã
commit nhưng wrapped key vẫn là bản cũ. Remote contract kiểm tra trực tiếp field
wrapped key đổi ở revision 2.

Vault-key rotation cũng dùng RPC này và không cần schema migration: client gửi
ciphertext đã mã hóa bằng DEK mới cùng wrapped DEK mới. Contract xác minh revision,
ciphertext và wrapped-key ciphertext đổi atomically. Backend không thể phân biệt
re-wrap với DEK rotation và không được xem là nơi xác nhận crypto semantics; test
client chứng minh DEK cũ không decrypt được revision mới.

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

Plaintext datasource/repository/use case không còn annotation DI. Release guard
vẫn chặn compatibility bridge ngay cả khi build flag bị đặt nhầm.

## Migration compatibility

`synced_accounts` vẫn tồn tại để giữ rollback/migration option. Nó chứa plaintext
`secret_key` nên:

- không dùng cho client release mới;
- không cấp thêm quyền hoặc bật lại bằng config production;
- backup trước drop;
- migration plaintext sang E2EE phải validate → encrypt → atomic publish → verify
  trước khi xóa row cũ.

Hiện production instance đã clean legacy app data; không có row cần client migrate.

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

Targeted registry contract:

    scripts/supabase/test_remote_device_registry_contract.sh \
      /path/to/supabase/.env https://api.example.com

Contract tạo hai user/ba session, kiểm tra no-direct-table/anonymous/cross-tenant,
current marker, self-revoke reject, targeted refresh/JWT revoke và current session
survival rồi xóa cả test user.

Recovery và Studio:

    scripts/supabase/test_remote_recovery_contract.sh \
      /path/to/supabase/.env https://api.example.com \
      https://auth.example.com/reset-password/

    scripts/supabase/test_remote_studio_proxy.sh https://studio.example.com

Baseline production ngày 18-07-2026: encrypted **20/20**, recovery 8/8 và Studio
proxy contract pass. Sau contract, test user và encrypted row đều được cleanup.

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
  `2.14.0` và MariaDB `10.5.29` đã pin exact current digest, không còn `latest`/
  floating patch tag. Target `2.15.1` cần backup/canary vì đổi Debian/OpenResty/
  Certbot và tác động mọi public domain.
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

## Device-wrap migration — **Đã deploy production**

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

## Khoảng trống đã biết

- SMTP mailbox delivery/expired-token E2E chưa có.
- External alert channel chưa cấu hình.
- `synced_accounts` chưa drop để giữ rollback path.
- Device registry production mới thu hồi auth session. Device-specific wrapped
  DEK client/migration/RPC đã deploy và pass focused + local PostgreSQL + remote
  regression + Linux/Android/iOS runtime; còn physical two-device/independent
  review. Remote
  wipe local vault không nằm trong thiết kế.
