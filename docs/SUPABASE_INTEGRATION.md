# Tích hợp Supabase

Supabase cung cấp Auth, password recovery và account-managed TOTP sync. TOTP
local không phụ thuộc Supabase.

## Client config

```json
{
  "SUPABASE_URL": "https://supabase.example.com",
  "SUPABASE_PUBLISHABLE_KEY": "TEST_ONLY_PUBLIC_KEY",
  "PASSWORD_RECOVERY_URL": "https://authenticator.example.com/reset-password"
}
```

Không commit production config. Service-role, JWT secret, Vault root key, DB/SSH
hoặc SMTP credential không được đưa vào Flutter build. Thiếu toàn bộ config thì
app local-only; partial/non-HTTPS config fail closed.

## Authentication

- Supabase sở hữu session persistence.
- Login/register/reset/update password đi qua Auth repository.
- Session restore/sign-in kích hoạt sync tự động.
- Logout dừng sync nhưng giữ local TOTP và cloud data.

## Canonical database contract

```text
supabase/migrations/20260804000000_create_account_managed_sync.sql
supabase/migrations/20260805000000_add_account_sync_realtime_signal.sql
supabase/migrations/20260805010000_fix_account_sync_realtime_authorization.sql
```

Migration tạo:

- `public.authenticator_accounts` với composite owner/account PK, revision,
  Vault secret reference và tombstone;
- private payload validator và Vault cleanup trigger;
- RPC `list_authenticator_accounts()`;
- RPC `upsert_authenticator_account(uuid,bigint,jsonb)`;
- RPC `delete_authenticator_account(uuid,bigint)`.

Table bật RLS/FORCE RLS nhưng không grant direct CRUD cho client. RPC là
security-definer, tự lấy `auth.uid()` và không nhận `user_id` từ request.

Migration Realtime additive tạo private trigger/function và own-topic `SELECT`
policy trên `realtime.messages`. Không cấp client `INSERT`, không publish
`authenticator_accounts` qua Postgres Changes và không thay đổi Vault row.
Corrective migration bỏ predicate `messages.private` vì authorization probe của
Realtime 2.102.3 chỉ populate topic/extension; private boundary vẫn do channel
join `private=true` và `realtime.send(..., true)` bắt buộc.

## Private Realtime

- Event `account-sync-changed` chỉ chứa `version=1` và generated message ID.
- Topic `account-sync:<auth.uid()>` chỉ join được với authenticated JWT cùng user.
- Database trigger phát sau account insert/update/tombstone.
- Client nhận event/reconnect rồi gọi RPC full sync; WebSocket không mang account
  payload và không thay CAS/tombstone semantics.
- Realtime là best-effort; resume/pull-to-refresh/retry vẫn bắt buộc.

## Vault và payload

- Upsert live record gọi `vault.create_secret`/`vault.update_secret`.
- Table/backup chỉ giữ authenticated ciphertext + reference.
- List RPC join `vault.decrypted_secrets` và trả plaintext cho đúng authenticated
  owner.
- Delete chuyển row thành tombstone, null secret reference rồi xóa Vault secret.
- Xóa auth user hard-delete row và trigger dọn Vault secret còn live.

Server có quyền decrypt; không gọi contract này là E2EE.

## CAS và tombstone

- Create: `expected_revision=0`, kết quả revision 1.
- Update: expected phải bằng current, kết quả N+1.
- Stale expected: `PT409/revision_conflict`.
- Upsert tombstone: `PT410/account_deleted`, không revive.
- Delete vắng với expected 0 tạo tombstone revision 1; delete tombstone idempotent.
- Payload sai schema/bounds: SQLSTATE `22023`.

## Breaking migration

Migration drop `encrypted_vault_snapshots` và
`publish_encrypted_vault_snapshot(...)`. Không dual-write/fallback. Minimal E2EE
ciphertext không thể tự migrate vì server không có HA1 recovery key. Local vault
trên thiết bị không bị server migration tác động.

Production đã migrate ngày 04-08-2026 sau khi xác nhận Minimal E2EE có 0 row,
tạo/rehearse full backup và encrypted off-host copy. Không phát hành lại client
Minimal E2EE cũ vì remote contract đó đã bị gỡ.

## Local verification

```bash
scripts/supabase/test_account_sync_migration.sh
```

Harness dùng đúng image production `supabase/postgres:17.6.1.136` và kiểm tra
Vault ciphertext, RPC ACL/auth, tenant isolation, CAS, invalid payload, tombstone
và cleanup object cũ; đồng thời kiểm tra signal allowlist, own-topic RLS,
client-send denial và table không nằm trong Postgres Changes publication.

## Remote verification sau deploy

```bash
scripts/supabase/test_remote_account_sync_contract.sh \
  /secure/supabase-operator.env \
  https://supabase.example.com
```

Script tạo hai isolated user, kiểm tra cross-user boundary/create/update/delete/
tombstone rồi xóa user. Operator env 0600 nằm ngoài repository và không đi vào
Flutter process/shell trace.

## Rollout

1. Maintenance: chặn cloud write từ client Minimal E2EE cũ.
2. Read-only production identity/row-count/Vault health audit.
3. Full backup + checksum + encrypted off-host copy + restore rehearsal ở mode
   `minimal`.
4. Apply migration bằng operator credential ngoài repository.
5. Reload PostgREST schema cache nếu cần; chạy health + remote contract.
6. Tạo post-migration backup, backup Vault root key/stack config và rehearse
   restore ở mode `account-sync`.
7. Phát hành client mới; theo dõi RPC/Auth/DB/storage growth.

Rollback backend dùng full pre-migration backup **cùng đúng Vault/root/config**.
Rollback app về local-only an toàn; app Minimal E2EE cũ không tương thích schema
mới.

## Khoảng trống

- Remote production contract đã pass 26/26 và iOS Simulator account-sync +
  private Realtime runtime đã pass; Android/Linux/Web runtime tương đương chưa
  có evidence mới.
- SMTP delivery và expired/reused password link E2E chưa xác minh.
- Chưa có external alert/off-host restore SLA và tombstone retention job.
