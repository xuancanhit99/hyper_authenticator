# Vận hành Supabase production

Runbook này mô tả account-managed automatic sync theo ADR-0020. URL, key,
password, SSH identity và backup thật nằm ngoài repository. Không chạy operator
script với `set -x`.

## Boundary production

- Self-hosted Supabase dùng exact pin trong `supabase/UPSTREAM_PIN`.
- Public traffic đi qua reverse proxy; database/compose port không expose tùy ý.
- Flutter chỉ nhận public URL, publishable key và password-recovery URL.
- Service-role/DB/SSH/SMTP/Vault/signing secret nằm ngoài Git, mode 0600/0640.
- TOTP payload được Supabase Vault mã hóa khi lưu nhưng authenticated backend RPC
  có thể giải mã; đây không phải zero-knowledge E2EE.

## Health check

```bash
sudo -n env \
  API_ORIGIN=https://supabase.example.com \
  RECOVERY_ORIGIN=https://authenticator.example.com \
  scripts/supabase/check_production_health.sh
```

Sau rollout ADR-0020, script xác minh core container/resource, backup/restore
evidence, public Auth/password-recovery route và account-sync contract:

- `authenticator_accounts` cùng Vault extension tồn tại;
- RLS + FORCE RLS bật, client không có direct table CRUD;
- list/upsert/delete RPC là security-definer và chỉ `authenticated` được gọi;
- Minimal E2EE/legacy plaintext object không còn.

Health script account-sync sẽ fail có chủ đích trước khi migration mới được
deploy. Dùng read-only preflight riêng để audit production đang chạy schema cũ.

## Full backup

```bash
sudo -n env \
  COMPOSE_DIR=/opt/stacks/supabase \
  BACKUP_ROOT=/home/operator/backups/hyper-authenticator/scheduled \
  scripts/supabase/backup_production.sh
```

Backup gồm PostgreSQL custom dump + globals, quiesced Storage filesystem,
sensitive stack config, manifest và `SHA256SUMS`. Nó chứa credential/data
production; không tải vào repository, issue hoặc CI artifact. Harness chờ
Storage healthy tối đa 180 giây sau restart và fail-closed nếu quá hạn.

## Restore rehearsal

Post-migration account-sync dùng mode mặc định:

```bash
sudo -n scripts/supabase/rehearse_backup_restore.sh \
  /home/operator/backups/hyper-authenticator/scheduled/supabase-YYYYMMDDTHHMMSSZ
```

Backup account-sync trước additive Realtime migration dùng:

```bash
sudo -n env RESTORE_SCHEMA_MODE=account-sync-pre-realtime \
  scripts/supabase/rehearse_backup_restore.sh /path/to/pre-realtime-backup
```

Fresh backup trước migration 2026-08-04 vẫn là Minimal E2EE nên phải rehearse:

```bash
sudo -n env RESTORE_SCHEMA_MODE=minimal \
  scripts/supabase/rehearse_backup_restore.sh /path/to/fresh-pre-migration-backup
```

Mode `pre-minimal` chỉ dành cho backup lịch sử trước 2026-08-02. Rehearsal luôn
restore vào database tạm ngẫu nhiên, kiểm tra schema/data/ACL rồi drop database;
không restore đè production.

Scheduled drill dùng `run_scheduled_restore_drill.sh`,
`check_restore_drill_state.sh` và systemd templates trong `supabase/systemd`.

## Encrypted off-host copy

```bash
OPERATOR_ENV=/secure/operator.env \
AGE_RECIPIENT_FILE=/secure/age-recipient.txt \
AGE_IDENTITY_FILE=/secure/age-identity.txt \
DESTINATION_ROOT=/secure/off-host/supabase \
scripts/supabase/pull_encrypted_backup.sh
```

Remote tar stream đi thẳng vào `age`; không tạo local plaintext archive. Phải
verify checksum và decrypt-stream listing. Backup/move Supabase Vault bắt buộc
giữ đúng Vault root key/stack config tương ứng.

## Breaking rollout account-managed sync

### Preflight

1. Đóng cloud write của client Minimal E2EE cũ/đặt maintenance.
2. Xác nhận đúng host, compose project, database và image pin bằng read-only
   inspection.
3. Audit `encrypted_vault_snapshots` row count. Dừng nếu khác 0 hoặc có dữ liệu
   chưa được owner chấp nhận bỏ.
4. Tạo full backup mới, checksum và catalog verification.
5. Rehearse backup đó với `RESTORE_SCHEMA_MODE=minimal`.
6. Tạo encrypted off-host copy, verify, và ghi backup ID/checksum/operator/time
   vào private evidence store.

### Apply

Từ repository revision đã review:

```bash
docker exec -i supabase-db \
  psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
  < supabase/migrations/20260804000000_create_account_managed_sync.sql
```

Migration chạy trong transaction, drop snapshot/RPC Minimal E2EE và tạo
Vault-backed per-account sync. Không sửa tay partial schema nếu command fail;
giữ maintenance và rollback bằng full backup khi cần.

### Verify remote

```bash
scripts/supabase/check_production_health.sh

scripts/supabase/test_remote_account_sync_contract.sh \
  /secure/supabase-operator.env \
  https://supabase.example.com

scripts/supabase/test_remote_recovery_contract.sh \
  /secure/supabase-operator.env \
  https://supabase.example.com \
  https://authenticator.example.com/reset-password/

scripts/supabase/test_remote_studio_proxy.sh \
  https://studio.example.com
```

Account-sync contract dùng service-role chỉ để tạo/dọn hai isolated user. Nó
kiểm tra anonymous/direct-table denial, tenant isolation, create/update/CAS,
tombstone/no-revival và object cũ absent. Sau suite phải xác minh test users,
rows và Vault secret fixture không còn.

Sau verify, tạo post-migration full backup, rehearse mode `account-sync` và tạo
encrypted off-host copy mới trước khi mở client ADR-0020.

### Runtime smoke

- Android emulator/iOS Simulator:
  `scripts/agent/mobile_account_sync_operator.sh`.
- Linux container:
  `scripts/agent/linux_account_sync_operator.sh`.
- Thiết bị thật chỉ dùng test account riêng; không cho harness reset local vault
  của người dùng.

Smoke phải chứng minh upload, thiết bị mới download không cần key phụ, delete tạo
tombstone và isolated user được dọn.

## Additive rollout private Realtime signal

Migration ADR-0021 không sửa account/Vault row nhưng thay authorization trên
`realtime.messages` và thêm trigger. Trình tự:

1. Xác minh Realtime container healthy, version pin và các object
   `realtime.send(jsonb,text,text,boolean)`, `realtime.topic()` cùng
   `realtime.messages` RLS tồn tại.
2. Tạo fresh full backup; rehearse với
   `RESTORE_SCHEMA_MODE=account-sync-pre-realtime`; tạo encrypted off-host copy.
3. Apply migration trong transaction:

```bash
docker exec -i supabase-db \
  psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
  < supabase/migrations/20260805000000_add_account_sync_realtime_signal.sql

docker exec -i supabase-db \
  psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
  < supabase/migrations/20260805010000_fix_account_sync_realtime_authorization.sql
```

Migration corrective thứ hai là bắt buộc với Realtime 2.102.3: server kiểm tra
private join bằng probe row chỉ có topic/extension, nên RLS không được phụ thuộc
nullable column `messages.private`. Privacy vẫn được khóa ở private channel và
`realtime.send(..., true)`.

4. Chạy health và `test_remote_account_sync_contract.sh`. Remote suite phải
   chứng minh own-topic receive, cross-user/client-send denial, signal allowlist
   và cleanup isolated user/row/Vault secret.
5. Tạo post-migration backup, rehearse mode `account-sync`, tạo encrypted
   off-host copy rồi chạy iOS/Android foreground runtime smoke.

Evidence production 05-08-2026:

- pre-backup `supabase-20260805T154247Z`: checksum, restore
  `account-sync-pre-realtime`, encrypted off-host verify pass;
- migration gốc + corrective migration apply trong transaction;
- health pass, remote contract 26/26 và cleanup test user/row/Vault orphan = 0;
- iOS Simulator pass remote-only upsert/delete qua Realtime;
- post-backup `supabase-20260805T161016Z`: checksum, restore `account-sync` và
  encrypted off-host verify pass.

Rollback additive:

```sql
drop trigger if exists broadcast_account_sync_change
  on public.authenticator_accounts;
drop function if exists private.broadcast_account_sync_change();
drop policy if exists account_sync_receive_own_broadcast
  on realtime.messages;
```

Rollback không xóa/sửa account/Vault data. Client vẫn dùng resume/refresh/retry
full sync khi không có signal.

## Rollback

- App: rollback về artifact local-only đã xác minh; không bật compatibility path.
- Database: full pre-migration backup trên version-matched stack cùng Vault root
  key/config.
- Client Minimal E2EE cũ không tương thích schema account-sync mới.
- Local TOTP trên thiết bị không nằm trong server rollback.

## Incident notes

- Backend/Vault root leak: coi toàn bộ cloud TOTP có khả năng bị lộ; rotate server
  credential/session, audit, thông báo và yêu cầu rotate TOTP tại issuer khi cần.
- User auth/session leak: revoke session, đổi password và audit account RPC.
- Lost device: revoke Supabase session không remote-wipe local vault.
- Backup failure: không xóa bản cuối hợp lệ; sửa capacity/permission rồi chạy lại
  backup + rehearsal.
- Sync deletion bất thường: đóng write, giữ local client offline và phục hồi
  backend từ backup đã rehearse; tombstone retention chưa được tự động compact.

## Nginx Proxy Manager

NPM có runbook riêng tại
[`supabase/nginx-proxy-manager/README.md`](../../supabase/nginx-proxy-manager/README.md).
Không nâng NPM chỉ vì app migration.

## Khoảng trống

- External alert destination và off-host/PITR SLA độc lập máy cá nhân.
- SMTP mailbox/expired-reused password-link E2E.
- Tombstone retention/compaction và workload/soak production.
- Independent review của Vault/RPC/root-key custody.

## Evidence account-managed sync 04-08-2026

- Pre-migration backup `supabase-20260803T201859Z`: checksum, restore mode
  `minimal` và encrypted off-host verify pass.
- Migration `20260804000000_create_account_managed_sync.sql` apply trong
  transaction; PostgREST schema cache đã reload.
- Remote account-sync contract pass 25/25; final audit có 0 account row, isolated
  user, Vault test secret hoặc orphan sync secret.
- Post-migration backup `supabase-20260803T202501Z`: checksum, restore mode
  `account-sync` và encrypted off-host verify pass.
- Operator scripts trên host đã được cập nhật; scheduled restore-drill evidence
  và production health đều pass.
- iOS Simulator isolated runtime pass upload/new-device-download/tombstone và
  cleanup user.

## Evidence lịch sử Minimal E2EE 02-08-2026

- Pre-migration backup `supabase-20260802T041022Z`: checksum, restore mode
  `pre-minimal` và encrypted off-host verify pass.
- Post-migration backup `supabase-20260802T041731Z`: checksum, restore mode
  `minimal` và encrypted off-host verify pass.
- Remote RLS/CAS suite pass 21/21; isolated users cleanup verified.
- Final audit có 0 snapshot/test user/temp restore DB; legacy object absent.

Evidence trên là lịch sử rollback trước ADR-0020, không phải bằng chứng rằng
account-managed sync đã được deploy.
