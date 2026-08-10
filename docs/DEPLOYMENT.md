# Deployment

## Kênh hiện tại

GitHub Releases là binary channel hiện tại; store rollout để sau.

| Target | Artifact | Stable gate còn lại |
|---|---|---|
| Android | Signed APK | physical camera/biometric/upgrade; Play Store sau |
| iOS | Local Development/Ad Hoc | account-sync physical runtime; TestFlight/App Store sau |
| macOS | Release compile | Developer ID/notarization |
| Windows | Unsigned NSIS preview | code signing + physical runtime |
| Linux | Unsigned `.deb` preview | representative desktop/keyring |
| Web | HTTPS/Nginx | browser camera/storage/account-sync runtime |
| Chrome Extension | MV3 Side Panel ZIP GitHub Preview | clean-profile vault/session/sync/restart evidence trước stable/store; privacy/support URL và Chrome Store review |

## Release gate

```bash
scripts/agent/check.sh full
```

Ngoài gate tự động: build bằng public production config, verify signer/checksum/
provenance, install/upgrade/launch smoke, kiểm tra artifact/log không chứa secret,
và cập nhật release notes/known limitations.

## Public config

Cloud-enabled build cần HTTPS Supabase URL, publishable key và HTTPS password
recovery URL. Service-role/DB/SSH/SMTP/Vault/signing private key chỉ nằm trong
server/CI secret store, không trong Flutter asset.

## Account-sync production rollout

Migration `20260804000000_create_account_managed_sync.sql` phá tương thích Minimal
E2EE remote contract. Local TOTP không nằm trong database migration.

### Trước migration

1. Thông báo maintenance và chặn client cũ cloud write.
2. Xác minh đúng host/compose/database bằng read-only check.
3. Audit `encrypted_vault_snapshots` row count; dừng nếu có dữ liệu cần giữ.
4. Full backup/checksum/catalog + encrypted off-host copy.
5. Restore rehearsal fresh backup với `RESTORE_SCHEMA_MODE=minimal`.
6. Xác minh Vault root key/stack config nằm trong backup custody.

### Migration

1. Apply đúng SQL bằng operator credential ngoài repository.
2. Không sửa tay partial object khi transaction fail.
3. Chạy health và `test_remote_account_sync_contract.sh`.
4. Xác minh old object absent, Vault/RPC/RLS/ACL/CAS/tombstone đúng.
5. Cleanup isolated users/rows và kiểm tra Vault secret không orphan.

### Sau migration

1. Post-migration full backup + restore rehearsal mode `account-sync`.
2. Deploy client mới; smoke sign-in/upload/new-device-download/delete.
3. Theo dõi Auth/PostgREST/DB/Nginx lỗi và Vault/tombstone growth.

### Rollback

- App có thể rollback về local-only; không bật lại hidden compatibility path.
- Database rollback bằng full pre-migration backup và version-matched stack.
- Client Minimal E2EE cũ không dùng được schema account-sync mới.

Runbook: [SUPABASE_PRODUCTION_OPERATIONS.md](operations/SUPABASE_PRODUCTION_OPERATIONS.md).

Production đã hoàn thành các bước migration/remote contract/backup ngày
04-08-2026. iOS Ad Hoc `1.1.0 (12)` đã upgrade-install và launch trên iPhone 16
Pro; iOS Simulator account-sync acceptance đã pass. Android/Linux/Web runtime và
public GitHub/store rollout của client mới vẫn là gate phát hành tiếp theo.

## Private Realtime additive rollout

Hai migration `20260805000000_add_account_sync_realtime_signal.sql` và
`20260805010000_fix_account_sync_realtime_authorization.sql` không rewrite
account/Vault data nhưng vẫn cần fresh backup và restore rehearsal
`account-sync-pre-realtime` trước apply. Sau apply phải xác minh:

1. trigger/function/policy tồn tại và account table không vào Postgres Changes;
2. own-user private topic join được, cross-user join và client send bị từ chối;
3. signal không chứa credential/account metadata;
4. remote contract cleanup sạch, post-backup rehearse mode `account-sync`;
5. platform smoke chứng minh remote mutation đánh thức foreground client.

Rollback drop đúng trigger/function/policy; RPC/Vault/account rows không đổi.

Production hoàn tất ngày 05-08-2026: pre-backup
`supabase-20260805T154247Z`, remote contract 26/26, iOS Simulator remote-only
upsert/delete pass, post-backup `supabase-20260805T161016Z`; cả hai backup đều
full restore rehearsal và encrypted off-host verify thành công. Ad Hoc
`1.1.0 (13)` đã ký, artifact secret scan pass và upgrade-install trên iPhone 16
Pro; auto-launch bị iOS chặn vì thiết bị đang khóa.

Android physical qua ADB Wi-Fi đã upgrade-install/launch release-mode build 13.
Thiết bị trước đó dùng debug certificate, nên bản device-test được ký lại bằng
đúng certificate đó để giữ local data. APK production ký bằng HyperZ upload key
đã verify riêng và không được cài đè lên debug-signed package; bản device-test
không phải artifact phát hành.

## GitHub Preview release

Workflow phải xuất đúng asset/checksum/signature contract. Android chỉ gọi signed
khi certificate fingerprint khớp pin. Windows/Linux unsigned phải ghi Preview.

Release public đã xác minh hiện tại:

- Public pre-release: [`v1.1.2-preview.3`](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.2-preview.3).
- Package version `1.1.2+16`, source commit
  `b0a0d983ced69b405c5c3063a2ef90219772470e`.
- Exact tag CI run [`31394148750`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31394148750)
  pass 8/8 Android/Apple/Web/Linux/Windows/Extension, quality và secret-history.
- Publish workflow [`31395060378`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31395060378)
  pass và tạo public non-draft pre-release từ exact tag artifact.
- Public verifier [`31395351977`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31395351977)
  tải lại như người dùng chưa đăng nhập và xác nhận đúng 9 asset, GitHub digest,
  checksum/manifest, Android signer pin, Debian package, Windows PE32 và Chrome
  Extension package ngày 10-08-2026.
- Android APK đã ký; Windows x64 installer và Linux amd64 Debian package chưa
  code-sign. iOS/macOS không thuộc asset contract của Preview này.

## Web

Flutter Web dùng public runtime config và Nginx serving contract. Account sync
được hỗ trợ nhưng browser profile/origin/XSS là trust boundary; release notes
không được gọi là native-equivalent secure storage hoặc E2EE.

## Chrome Extension

Chrome Extension foundation tạo ZIP qua `scripts/agent/build_chrome_extension.sh`.
Manifest chỉ xin `sidePanel` và host permission Supabase production; không mở
page access/autofill. Package verifier bắt buộc MV3, local CanvasKit/WASM,
extension CSP, không remote executable/ZXing CDN/PWA worker, không có path
xung đột trên filesystem không phân biệt hoa/thường và encrypted vault bridge
có AES-GCM key non-extractable.

CI tạo artifact từ GitHub Actions Variables `SUPABASE_URL`,
`SUPABASE_PUBLISHABLE_KEY` và `PASSWORD_RECOVERY_URL` qua file runtime tạm
0600. Đây là public client config; service-role, database/SSH/SMTP/Vault key
không được truyền vào job hoặc package.

ZIP được đưa vào GitHub Preview khi owner xác nhận waiver runtime acceptance qua
workflow release; package phải có exact CI provenance, SHA-256, static verifier
và release note bắt buộc nói rõ `owner-waived`. Waiver chỉ cho GitHub Preview,
không phải bằng chứng security sign-off, stable release hoặc Chrome Web Store.

Trước stable/store distribution cần:

1. chạy clean profile load/unload/restart/tamper/local-vault smoke;
2. test login/session restore, cross-device RPC sync/tombstone và Realtime
   foreground wake-up bằng account isolated;
3. review permission/CSP/source ZIP độc lập, checksum/provenance và no-secret log;
4. public privacy policy, support/security contact, in-product cloud disclosure,
   artwork store (screenshot/promo) và Chrome developer/store review;
5. Trusted Testers/limited rollout trước public store.

## Signing material

- Android JKS: encrypted Actions secrets + ít nhất hai encrypted/offline backup.
- Apple: Keychain/Developer Portal/CI secret store, profile khớp bundle/device.
- Windows/macOS: private signing/notarization credential trong secure CI.

## Input còn hoãn

- SMTP mailbox delivery.
- Public privacy/support/security-contact URL.
- External alert destination và off-host backup SLA.
- Store metadata/account/certificate.
