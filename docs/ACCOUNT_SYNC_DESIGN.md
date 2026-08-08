# Thiết kế account-managed sync

Tài liệu chuyên sâu này bổ sung cho [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md) và
[ADR-0020](adr/0020-account-managed-automatic-sync.md).

## Product contract

- Không session: local-only.
- Có session: tự merge mã thuộc user hiện hành.
- Thiết bị mới: chỉ đăng nhập, không recovery key.
- Add/update/import/delete: local commit trước, cloud retry sau.
- Logout: dừng sync, giữ local/cloud.

## Consistency

Mỗi record có stable UUID và monotonic server revision. Client giữ fingerprint
của version đã sync. Local fingerprint khác nghĩa là dirty. CAS conflict refresh
remote rồi retry local intent một lần.

Delete dùng tombstone và có precedence cao hơn update. RPC không cho upsert một
tombstone, vì vậy stale device không resurrect account.

## Ownership

Local account chưa owner được bind với user đăng nhập đầu tiên trước mọi network
call. Binding nằm trong secure storage và được re-read verify. Account đã bind
user khác vẫn hiện/dùng local nhưng không đi vào request của user hiện hành.

## Encryption/trust

Payload live được Supabase Vault authenticated-encrypt trên disk. Authenticated
security-definer RPC có thể decrypt cho đúng `auth.uid()`. Backend/Vault key
holder vì vậy nằm trong trust boundary; không gọi đây là E2EE.

## Failure/rollback

- Network/RPC fail: local + pending metadata giữ nguyên.
- Metadata corrupt/write fail: dừng trước network.
- Remote payload invalid: không mutate local.
- Rollback client: chạy local-only.
- Rollback backend: restore full backup cùng version-matched Vault root/config.

## Chưa có

- Realtime/background polling.
- Ownership transfer UI.
- Tombstone retention.
- Remote wipe local vault.
