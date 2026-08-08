# Mô hình dữ liệu

## AuthenticatorAccount

```json
{
  "id": "UUID",
  "issuer": "Service",
  "accountName": "account label",
  "secretKey": "REDACTED",
  "algorithm": "SHA1",
  "digits": 6,
  "period": 30
}
```

- `id`: stable UUID dùng chung local/cloud.
- `issuer`, `accountName`: display metadata.
- `secretKey`: Base32 credential, không log/analytics.
- `algorithm`: SHA1/SHA256/SHA512; `digits`: 6–8; `period`: số giây dương.
- Legacy record thiếu optional parameter đọc theo SHA1/6/30 và phải round-trip.

## Local vault v2

```text
ha:v2:record:<record-id>
ha:v2:manifest:<generation>:<transaction-id>
ha:v2:commit:<generation>:<transaction-id>
```

Commit marker publish một generation đã verify. Reader có thể lùi về generation
hợp lệ trước; compaction giữ hai generation gần nhất. Write/delete/import/replace
được serialize.

## Chrome Extension encrypted store

Chrome Extension không đổi key/JSON của local vault v2 hoặc sync metadata. Nó
đổi **container** phía dưới thành IndexedDB origin của extension:

```text
database: hyper-authenticator-extension-v1
keys[vault-key]     = CryptoKey AES-256-GCM, extractable=false
records[logicalKey] = { iv: ArrayBuffer(12), ciphertext: ArrayBuffer }
```

`logicalKey` giữ nguyên `ha:v2:*`, `ha:cloud-sync:v1:metadata` hoặc namespace
Supabase extension. AAD là `hyper-authenticator-extension-v1:<logicalKey>`;
copy ciphertext giữa key khác phải decrypt fail. Raw key không có serialization,
không ghi vào localStorage/chrome.storage và không portable sang profile khác.

Supabase session/PKCE record là implementation detail tách namespace, không là
model account/cloud protocol và không được log.

## Sync metadata v1

Secure-storage key:

```text
ha:cloud-sync:v1:metadata
```

Value:

```json
{
  "formatVersion": 1,
  "records": {
    "<account-uuid>": {
      "ownerUserId": "<supabase-user-uuid>",
      "remoteRevision": 3,
      "syncedFingerprint": "base64url-sha256-or-null",
      "isDeleted": false
    }
  }
}
```

- Ownership được persist/verify trước network call đầu tiên.
- Fingerprint là SHA-256 của canonical full account JSON và nằm trong secure
  storage; không dùng làm encryption/auth credential.
- `remoteRevision=0` nghĩa là chưa publish.
- Metadata live nhưng local record vắng là pending delete intent.
- Corrupt/unknown version fail closed, không reset âm thầm.

## Supabase table

`public.authenticator_accounts`:

| Column | Contract |
|---|---|
| `user_id` | FK `auth.users`, một phần composite PK |
| `account_id` | stable UUID, một phần composite PK |
| `revision` | bigint > 0, tăng qua CAS |
| `vault_secret_id` | reference tới Vault ciphertext; null khi tombstone |
| `updated_at` | UTC server timestamp |
| `deleted_at` | null nếu live, UTC timestamp nếu tombstone |

Invariant: live record có `vault_secret_id`; tombstone không có secret reference.
Authenticated client không có direct table ACL.

## RPC payload

Live RPC record:

```json
{
  "account_id": "UUID",
  "revision": 1,
  "updated_at": "UTC timestamp",
  "deleted_at": null,
  "payload": {
    "issuer": "Service",
    "accountName": "account label",
    "secretKey": "REDACTED",
    "algorithm": "SHA1",
    "digits": 6,
    "period": 30
  }
}
```

Tombstone có `payload=null` và `deleted_at!=null`. SQL validator chỉ nhận đúng
sáu payload key, bounded strings, Base32 secret, supported algorithm/digits và
period 1–300.

RPC:

- `list_authenticator_accounts()`;
- `upsert_authenticator_account(account_id, expected_revision, payload)`;
- `delete_authenticator_account(account_id, expected_revision)`.

`user_id` không phải client parameter; function lấy `auth.uid()`.

## Realtime wake-up signal

Các migration `20260805000000_add_account_sync_realtime_signal.sql` và
`20260805010000_fix_account_sync_realtime_authorization.sql` không đổi account
row. Trigger phát private Broadcast:

```json
{"version": 1, "id": "REALTIME_GENERATED_UUID"}
```

Topic là `account-sync:<auth.uid()>`, event `account-sync-changed`. Message không
chứa account UUID/revision/payload/Vault reference và không phải nguồn sự thật;
client luôn gọi RPC sync sau khi nhận. `realtime.messages` là transport-managed,
không phải application backup/data model dài hạn.

Authorization probe của Realtime chỉ có topic/extension, nên nullable field
`messages.private` không nằm trong RLS predicate. Client vẫn bắt buộc join
private channel và database signal luôn gọi `realtime.send(..., true)`.

## Portability format

- Standard: `otpauth://totp/...` giữ algorithm/digits/period.
- Google migration: `otpauth-migration://offline?data=<protobuf-base64url>`;
  bounded multi-part batch, chỉ commit sau preview/validate-all.

## Theme preferences

| Key | Value |
|---|---|
| `theme_mode` | `system`, `light`, `dark` |
| `app_style` | enum name visual style |

## Contract đã loại bỏ

Không còn persisted contract cho HA1 recovery key, DEK, wrapped key, encrypted
snapshot, last snapshot revision, portable backup, device/session registry,
per-device key wrap hoặc key rotation. Không có compatibility fallback.
