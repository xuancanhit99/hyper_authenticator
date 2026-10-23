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

P1 storage rollout ngày 21-10-2026 theo ADR-0024 có migration local vault v3 và
native auth preferences sang secure storage. Không downgrade về writer v2 sau
upgrade. Giữ app/install identity; không clear-data/reinstall để sửa crypto error.
Android phải giữ path dependency `third_party/flutter_secure_storage` đã patch.
Build/runtime checks nằm trong task P1; sửa source chưa đồng nghĩa đã phát hành.

Ngày 21-10-2026 đã deploy Web `1.1.4+18` từ working tree bằng image
`hyper-authenticator-web:1.1.4-p1-20261021r2`. Public `main.dart.js` SHA256:
`46a7668a2ae8189a62611a8b24a908dd5e5fe8da59b4bbc2b0458128041ba5c1`.
Compose snapshot trước r2 giữ image r1 cũng hiểu vault v3; không dùng compose
trước P1 để downgrade writer sau khi client đã ghi v3. Recovery/backend không
đổi. APK signer khớp pin; cấu hình local đã chuyển từ keystore cũ sang khóa phát
hành đúng, lưu dưới thư mục backup operator ngoài Git. Không phân phối key.
Android physical đã update giữ data và launch; ở bước rollout này Windows/Linux/extension được
đóng gói để bàn giao local. Sau đó GitHub Preview `v1.1.5-preview.1` đã publish
từ exact-tag CI bên dưới; store rollout chưa thực hiện. Linux Debian build ở Ubuntu
24.04 không chứng minh tương thích distro có glibc cũ hơn.
Xem [task triển khai](tasks/2026-10-21-deploy-runtime.md) cho evidence và giới hạn.

Backup services cần cài `supabase/systemd/hyper-auth-backups.conf` vào tmpfiles.d
và chạy `systemd-tmpfiles --create` trước enable timer để tránh 226/NAMESPACE.
Xem runbook production cho off-host custody và drill.

```bash
scripts/agent/check.sh full
```

Ngoài gate tự động: build bằng public production config, verify signer/checksum/
provenance, install/upgrade/launch smoke, kiểm tra artifact/log không chứa secret,
và cập nhật release notes/known limitations.

Sau mỗi lần phát hành, maintainer đang dùng **Load unpacked** từ project phải cập
nhật source rồi build lại snapshot local:

```bash
git switch master
git pull --ff-only
scripts/agent/rebuild_chrome_extension_for_local_load.sh
```

Sau đó mở `chrome://extensions` và bấm **Reload** ở Hyper Authenticator. GitHub
Release và thay đổi Dart source không tự cập nhật
`build/chrome-extension/unpacked`; command fail closed nếu `.env` thiếu public
cloud config. Lần build đầu còn chuẩn bị khoảng 23 MB font fallback đã pin vào
cache `.dart_tool`; package chỉ được tạo sau khi đủ 724 WOFF2 + 144 OFL và mọi
checksum đều đúng.

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

- Public pre-release: [`v1.1.6-preview.1`](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.6-preview.1),
  app `1.1.6+20`, source `500c4dc6af7b5db10c9384d5d307e0eb9420fe2b`.
- PR #60 full CI 8/8, security 4/4 và GitGuardian pass. Exact-tag CI
  [`39999551127`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39999551127)
  pass 8/8, gồm signed APK, Windows/Linux upgrade/vault/runtime/installers,
  Web/extension và Apple compile. Master CodeQL/OSV có 0 findings/error.
- Publisher [`40001618205`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/40001618205)
  và independent public verifier
  [`40001851396`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/40001851396)
  pass ngày 24-10-2026: anonymous downloads đúng 9 assets, provenance/digests,
  SHA256, Android signer pin và package contracts.
- Logo Google nền trong suốt trên Login/Register được bundle offline; payload
  trong APK/extension khớp checksum source. Không đổi auth/vault/cloud contract.
- Windows/Linux unsigned Preview, Apple compile-only; giữ owner waiver và
  disclosure extension/native/physical acceptance gaps. Local extension unpacked
  đã rebuild và verify 1.1.6, owner cần Reload thủ công trong Chrome.
  Chi tiết [task release](tasks/2026-10-24-google-logo-release.md).

Release trước đã xác minh:

- Public pre-release: [`v1.1.5-preview.1`](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.5-preview.1),
  app `1.1.5+19`, source `8bf680bf37212eba1d5f0c1bc87a584e29bf3c7d`.
- [PR #57](https://github.com/xuancanhit99/hyper_authenticator/pull/57) squash merge
  P1/P2 và Google login/register vào `master`.
- Exact-tag CI [`39497379075`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39497379075)
  pass 8/8 jobs, gồm full quality/backend/secret gates, Android signed APK,
  Windows/Linux historical upgrade và runtime/installers, Web/extension,
  macOS release và iOS Simulator compile.
- Publisher [`39526492707`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39526492707)
  pass, tạo public non-draft pre-release từ đúng artifacts của tag.
- Public verifier [`39526579086`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39526579086)
  pass ngày 21-10-2026: anonymous download đúng 9 assets, metadata/provenance,
  GitHub digests, checksum/manifest, Android signer pin và package contracts.
- Android APK đã ký đúng signer pin. Windows installer/Linux Debian là unsigned
  Preview; không phân phối iOS/macOS binary. Extension runtime acceptance được
  owner waiver và công bố trong release notes; chưa phải Chrome Store acceptance.
- Vault v3 không downgrade về writer v2; Google session/consent hoàn chỉnh trên
  native/extension, physical camera/biometric và kiểm tra dài hạn còn pending.
  Chi tiết [task release](tasks/2026-10-21-github-release.md).

Release lịch sử đã xác minh:

- Public pre-release: [`v1.1.3-preview.1`](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.3-preview.1).
- Package version `1.1.3+17`, source commit
  `0a2105d1a7f7ecd92a537284977026fa94fcad34`.
- Exact tag CI run [`31406851631`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31406851631)
  pass 8/8 Android/Apple/Web/Linux/Windows/Extension, quality và secret-history.
- Publish workflow [`31407810354`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31407810354)
  pass và tạo public non-draft pre-release từ exact tag artifact.
- Public verifier [`31407979891`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31407979891)
  tải lại như người dùng chưa đăng nhập và xác nhận đúng 9 asset, GitHub digest,
  checksum/manifest, Android signer pin, Debian package, Windows PE32 và Chrome
  Extension package ngày 10-08-2026.
- Android APK đã ký; Windows x64 installer và Linux amd64 Debian package chưa
  code-sign. iOS/macOS không thuộc asset contract của Preview này.

Preview này bổ sung provider logo catalog local đã pin; Chrome Extension ZIP có
42.460.989 byte và Android APK có 100.997.481 byte sau khi bundle catalog.

## Web

Ngày 24-10-2026, Web production đã chạy `1.1.6+20`, image
`hyper-authenticator-web:1.1.6-logo-20261024`, logo Google sign-in nền trong suốt.
JS SHA256 `712592a60b51bbdd4d5b3f048a9b0091ad05ee59fc8eea55fb02641024448bac`.
Shadow rồi public serving/version/logo checksum và real Chrome Login/Register pass.
Private rollback snapshot `/opt/stacks/hyper-authenticator/compose.pre-logo-20261024.json`
giữ image `1.1.5-google-20261021` hiểu vault v3. Chỉ recreate Web, không đổi
provider, backend hoặc dữ liệu. Xem [task release](tasks/2026-10-24-google-logo-release.md).

Ngày 21-10-2026, production rollout Google dùng `1.1.5+19`, image
`hyper-authenticator-web:1.1.5-google-20261021`. Compose trước rollout là private
`compose.pre-google-20261021.json`; image trước `1.1.4-p1-20261021r2` hiểu vault v3.
Auth chỉ recreate service `auth` sau private env/compose backup; Google secret
không vào Docker build. Google callback là
`https://supabase-api.vnpay.dev/auth/v1/callback`; Google Cloud Audience/Publishing
quản lý bên ngoài app. Xem [task Google](tasks/2026-10-21-google-sign-in.md).

Flutter Web dùng public runtime config và Nginx serving contract. Account sync
được hỗ trợ nhưng browser profile/origin/XSS là trust boundary; release notes
không được gọi là native-equivalent secure storage hoặc E2EE.

## Chrome Extension

Chrome Extension foundation tạo ZIP qua `scripts/agent/build_chrome_extension.sh`.
Manifest xin `sidePanel`, `identity` và host permission Supabase production; không mở
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
