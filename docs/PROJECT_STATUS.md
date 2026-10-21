# Trạng thái dự án

Baseline được audit ngày **5 tháng 8 năm 2026** trên nhánh
`codex/minimal-e2ee`. Tên nhánh là lịch sử; source đã chuyển sang
account-managed automatic sync theo ADR-0020 và backend production đã được
migrate cùng ngày. Evidence source/package được cập nhật ngày **21 tháng 10 năm
2026**.

## Kết luận

Hyper Authenticator là ứng dụng TOTP Flutter đa nền tảng, local-first:

- Không đăng nhập: mã TOTP chỉ nằm trong local vault và dùng offline bình thường.
- Đăng nhập Supabase: mã thuộc tài khoản hiện hành tự upload/download; xóa tạo
  tombstone trên cloud và được áp xuống thiết bị khác.
- Không còn setup/import recovery key, DEK, encrypted snapshot, manual conflict
  hoặc nút “Backup ngay”.
- Cloud payload được mã hóa khi lưu bằng Supabase Vault nhưng backend có quyền
  giải mã qua authenticated RPC. Đây **không phải E2EE/zero-knowledge**.
- Import/export hỗ trợ standard `otpauth` và Google Authenticator migration QR.
- GitHub Releases là kênh binary hiện tại; store release vẫn để sau.
- Chrome Extension MV3 Side Panel đã có current-profile smoke: render, login,
  account sync và session còn sau đóng/mở Chrome. Owner đã cho phép đưa ZIP vào
  GitHub Preview với disclosure runtime acceptance bị waiver. Ngày 21-10 có thêm
  clean-profile extension-origin UI/session restart, cross-context vault/tamper
  và sync sang Web; native Side Panel host/cross-device vẫn pending, chưa Chrome Store.

## Đã triển khai trong source

### Security scanning ngày 22-10-2026

Dependabot alerts, malware alerts và tự tạo security-update PRs đã bật; lần kiểm
tra API đầu trả 0 dependency alerts. OSV v2.7.0 local quét 187 locked Pub packages
không có finding. [CodeQL/OSV PR run](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39658902219)
pass 4/4 jobs, SARIF 0 PR-diff results/error; chưa có Dart source analysis từ CodeQL.
GitGuardian đã ignore 3 incidents test fixtures bằng lý do false positive; repo
filter 0 open. Check PR #57 cũ trả neutral khi yêu cầu rerun vì provider không
rescan old checks; GitGuardian PR #58 pass. Cấu hình đã merge master qua PR #58.
Master baseline sau merge phát hiện 8 medium alerts trong code hiện có: 7 mutable
Flutter Action references và 1 file-to-CDP flow của test harness. Đang xác minh
follow-up pin SHA và loopback harness hardening; không gọi scan success là zero findings.
Xem [task security](tasks/2026-10-22-security-alerts.md).

### Merge và GitHub Preview release ngày 21-10-2026

P1/P2 và Google login đã squash merge qua
[PR #57](https://github.com/xuancanhit99/hyper_authenticator/pull/57) vào `master`,
commit `8bf680bf37212eba1d5f0c1bc87a584e29bf3c7d`, tag `v1.1.5-preview.1`.
[PR CI](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39495522362)
pass **8/8 jobs**, gồm full quality/backend/secret gates, Windows/Linux historical
vault upgrade và installer/runtime, Web/extension, macOS/iOS Simulator compile.
[Exact-tag CI](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39497379075)
cũng pass **8/8 jobs**. [Publisher](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39526492707)
đã phát hành [v1.1.5-preview.1](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.5-preview.1),
app `1.1.5+19`, với APK Android đã ký, Windows installer, Debian và extension ZIP.
Windows/Linux là unsigned Preview; iOS/macOS chỉ compile, không phân phối binary.
[Public verifier](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/39526579086)
pass: anonymous download đủ 9 assets, checksum/digest, provenance và signer pin.
Chi tiết xem
[task GitHub release](tasks/2026-10-21-github-release.md).

### Google login/register ngày 21-10-2026

Web production **1.1.5+19**, image `hyper-authenticator-web:1.1.5-google-20261021`,
có **Tiếp tục với Google** trên Login/Register. Supabase Google provider enabled,
signup enabled; owner xác nhận đăng nhập Google thành công trên Web. Không thay
vault v3, remote schema hoặc tự merge TOTP. Client Secret chỉ ở server và private
operator backup ngoài repo. Chi tiết [task Google](tasks/2026-10-21-google-sign-in.md)
và [ADR-0025](adr/0025-google-oauth-pkce.md).

Windows suite pass 328, skip 6; Linux suite pass 334; Linux analyzer không có issue.
Web real browser mở được Google chooser. Extension real isolated Chromium mở
Google identity window và hủy để thử lại được; chưa test Google session/consent
hoàn chỉnh trên extension/native. Android signed APK 1.1.5 đã upgrade-install lên
thiết bị physical, resolve đúng callback và launch; Windows release launch pass.
Ở bước rollout local, Apple builds chưa chạy và full gate Windows bị giới hạn
host/tooling. Exact-tag CI sau đó đã pass macOS release, iOS Simulator compile
và full quality gate trên Ubuntu; stable/store và device acceptance vẫn còn thiếu.

### P2 review ngày 19-10-2026

Nhánh `codex/fix-review-p2` sửa F08–F12: Base32 canonical trước sinh mã, URI
thiếu issuer, bounds admission/cloud và cô lập record legacy lỗi để không chặn
sync, password nguyên vẹn, clipboard chờ API xác nhận. Vault/metadata/SQL schema
không đổi trong task P2. Web đã deploy cùng P1 ngày 21-10-2026. Bảy P1 của review vẫn ngoài phạm vi
task P2; phần P1 được xử lý riêng bên dưới. Không dùng kết quả P2 để kết luận ứng dụng đã sẵn sàng phát hành.
Chi tiết kiểm chứng và giới hạn môi trường trong
[task P2](tasks/2026-10-19-review-p2.md).

### P1 review ngày 21-10-2026

Source sửa F01–F07 theo [ADR-0024](adr/0024-atomic-local-vault-sync-and-preservation.md):
vault v3 commit payload/owner/delete intent cùng nhau, generation CAS và retry
khi mutation chen giữa network; session đổi thì abort. Extension atomic key init,
Web Locks và missing-key fail closed đã qua real Chrome isolated contexts, kể cả
negative control với code cũ. Configured app lock không bypass khi support mất;
native Supabase session/PKCE migration verify-before-remove và logout tombstone.
Android plugin vendored tắt reset, bảo toàn corrupt backup và có restart-safe
migration cleanup, đã chạy Robolectric; physical Keystore/upgrade vẫn cần acceptance.

Server backup/restore-drill/health đã chạy thành công; encrypted off-host copy
đã kiểm chứng tại máy operator và có Windows task hàng ngày (chỉ chạy khi user
đăng nhập, chạy bù khi máy khả dụng). Không xem đó là off-host SLA độc lập với máy
operator. App fixes đã merge vào master trong task GitHub release; store rollout
vẫn chưa thực hiện.
Chi tiết lệnh, evidence và giới hạn trong [task P1](tasks/2026-10-21-review-p1.md).

### Build/deploy và runtime ngày 21-10-2026

Trước rollout Google `1.1.5+19`, Web production đã chạy `1.1.4+18`, image
`hyper-authenticator-web:1.1.4-p1-20261021r2`; shadow/public route, CSP,
no-store, dotfile denial và JS checksum đều pass. Browser smoke xác nhận local
TOTP persist, login, auto-sync, logout giữ mã và nhận account từ extension.
Windows runtime trong namespace riêng và Linux WSL/Xvfb với private keyring đều
pass local-vault và real Supabase sync (upload/new-device download/Realtime/delete).
Android AVD riêng pass local-vault; APK cuối khớp signer pin và đã upgrade-install
từ `1.1.2` lên `1.1.4` trên Android physical, launch/process còn sống.

Đây là bằng chứng working-tree deployment trước đợt exact-tag CI release bên trên. Windows portable
và Linux bundle/Debian là unsigned Preview; Debian được build trên Ubuntu 24.04
và yêu cầu glibc >=2.38. Apple toolchain không có trong phiên này. Camera,
biometric, physical vault contents/migration và kiểm tra dài hạn vẫn chưa được
chứng minh. Không dùng launch-only làm bằng chứng dữ liệu đã round-trip.
Evidence/artifact/checksum và cleanup trong
[task deploy/runtime](tasks/2026-10-21-deploy-runtime.md).

### TOTP và local vault

- Parse/validate bounded `otpauth://totp`, Base32, SHA1/SHA256/SHA512, digits
  6–8 và period dương.
- Thêm bằng camera, ảnh QR hoặc nhập tay theo capability platform.
- Import standard `otpauth`/Google migration qua preview, exact dedupe và atomic
  copy-on-write append.
- Protected QR export yêu cầu fresh OS authentication, timeout/lifecycle cleanup
  và không persist raw QR payload.
- Tìm kiếm, sửa, xóa, sao chép mã và countdown theo period.
- `FlutterSecureStorage` giữ local vault v3 copy-on-write; logout không xóa mã.

### Account-managed automatic sync

- `SyncBloc` global nghe session restore/sign-in/sign-out và mutation của
  `AccountsBloc`; app resume và pull-to-refresh cũng yêu cầu sync.
- Mỗi remote account có stable UUID, revision CAS và deletion tombstone.
- Thiết bị mới chỉ cần đăng nhập để tải mã; không cần recovery credential.
- Local mutation commit trước; network lỗi không rollback local. Pending
  create/update dựa trên secure ownership/revision/fingerprint; delete dùng intent
  persist cùng account snapshot và retry ở lần sync sau.
- Tombstone thắng update từ thiết bị offline, nên account đã xóa không tự sống
  lại.
- Account chưa có owner được bind bền vững với user đăng nhập đầu tiên **trước
  network call**. Account đã thuộc user A không tự upload sang user B.
- Logout dừng sync nhưng giữ local vault và ownership metadata.
- Private Realtime Broadcast theo user chỉ làm wake-up signal foreground;
  signal/reconnect được debounce rồi gọi cùng full sync RPC. Message không chứa
  account/Vault/TOTP data và client không có quyền phát.
- Web không còn bị tắt cloud sync chỉ vì thiếu native DEK; cùng contract RPC áp
  dụng cho các platform. Web vẫn có browser-storage risk riêng.

### UI, auth và platform

- Settings chỉ còn trạng thái “Đồng bộ với tài khoản”, login/logout và retry;
  không còn recovery/conflict/remove-cloud UI.
- Auth có email/password, Google login/register, session restore, quên/đổi mật khẩu.
- Presentation error boundary chỉ hiển thị copy cố định theo thao tác; raw lỗi
  Supabase/storage/network không đi vào UI. Validation local đã kiểm soát vẫn
  giữ hướng dẫn cụ thể.
- Accounts/Settings dùng `StatefulShellRoute.indexedStack`; theme có ba visual
  style × light/dark. Appearance/Product Info sheet dùng root navigator để
  không giữ modal route trong history riêng của Settings branch; preview style
  và mode chip có regression test cho border bo kín và icon không chồng lớp.
  Tab Accounts luôn vào initial location để không restore startup/app-lock
  overlay cũ rồi bị `returnTo=/settings` redirect ngược sau resume.
- Settings có mục Giới thiệu gọn: version, local-only, account sync, ranh giới
  xử lý dữ liệu và giấy phép mã nguồn mở. UI không tạo privacy/support action
  cho tới khi owner cung cấp URL/contact production.
- Provider đã nhận diện hiển thị logo local từ snapshot Sentinel Icons pin tại
  commit `626fd8d`: 1.076 image/1.201 issuer-alias, có MIT License, checksum và
  integrity gate. Provider không nhận diện hoặc asset lỗi fallback avatar ký tự;
  logo không nằm trong account/sync data.
- Maintainer có command fail-closed để rebuild snapshot Chrome **Load unpacked**
  từ source hiện tại với `.env` cloud-enabled; release/source mới không còn được
  mô tả như thể tự cập nhật thư mục output local.
- Chrome package self-host đủ catalog fallback của Flutter 3.44.6 bằng source
  lock URL/SHA-256 (724 WOFF2 + 144 OFL); verifier reject inventory sai/tamper,
  gồm regression `Noto Sans HK 104` thay cho contract một font Latin trước đây.
- App Lock dùng local authentication khi platform hỗ trợ. Privacy Shield che nội
  dung ngoài foreground nhưng không phải active screenshot prevention.

## Data contract hiện tại

- Local vault: format v3, giữ key prefix `ha:v2:` và đọc/migrate v1/v2.
- Sync metadata v1 embedded trong manifest; `ha:cloud-sync:v1:metadata` chỉ là
  nguồn migration, không còn writer độc lập.
- Remote migration mới:
  `supabase/migrations/20260804000000_create_account_managed_sync.sql`.
- Realtime migration additive:
  `supabase/migrations/20260805000000_add_account_sync_realtime_signal.sql`.
- Realtime authorization correction:
  `supabase/migrations/20260805010000_fix_account_sync_realtime_authorization.sql`.
- Table `public.authenticator_accounts` chỉ giữ owner/UUID/revision/Vault secret
  reference/timestamp/tombstone; authenticated client không có direct table ACL.
- RPC: `list_authenticator_accounts`, `upsert_authenticator_account`,
  `delete_authenticator_account`; tất cả bind `auth.uid()`.
- Migration drop Minimal E2EE snapshot/RPC cũ. Không dual-write hoặc fallback.

## Capability matrix của source

| Platform | TOTP local | QR camera | QR ảnh | App lock | Protected export | Account sync |
|---|---:|---:|---:|---:|---:|---:|
| Android | Có | Có | Có | Có | Có | Có |
| iOS | Có | Có | Có | Có | Có | Có |
| macOS | Có | Có | Có | Có | Có | Có |
| Windows | Có | Không | Không | Có | Có | Có |
| Linux | Có | Không | Không | Không | Không | Có |
| Web | Có | Có | Không | Không | Không | Có |
| Chrome Extension | Có | Không | Không | Không | Không | Có (khi Side Panel mở) |

Đây là source capability, không thay thế runtime/store evidence.

## Bằng chứng hiện tại

| Gate | Kết quả |
|---|---|
| P2 source verification 19-10-2026 | 288 Flutter test pass, 6 platform golden skip; scoped analyze 0 issue; Web release build, docs/platform/format pass; relative-output DI codegen hash khớp. Full gate chưa green do Windows tool/POSIX/output-path và Docker daemon; xem task P2. Không deploy production. |
| `flutter analyze` | Pass, 0 issue ngày 05-08-2026 |
| `flutter test` | Pass 242 test ngày 18-10-2026 |
| `scripts/supabase/test_account_sync_migration.sh` | Pass trên đúng `supabase/postgres:17.6.1.136`: Vault/RPC/CAS/tombstone và authorization probe đúng Realtime 2.102.3 |
| Full gate | `scripts/agent/check.sh full` pass ngày 11-08-2026: docs/codegen/format/analyze/platform, 242 Flutter test, migration/release/infra harness |
| Kiểm tra trước commit ngày 18-10-2026 | `scripts/agent/check.sh full`: docs/codegen/format/analyze/platform, 242 Flutter test và release/infra harness pass; backend migration gate chưa chạy được vì Docker daemon local đang tắt. Không có thay đổi schema/backend trong diff này. |
| Chrome Extension font package | Local cloud-enabled `1.1.3+17` build + package verifier pass ngày 11-08-2026: 724 WOFF2, 144 OFL, exact lock/checksum và tamper regression `Noto Sans HK 104`; runtime sau Reload chờ owner xác nhận |
| iOS Simulator account sync | UI auth giữ local vault + upload/download/tombstone + remote-only upsert/delete qua Realtime pass; isolated user cleanup verified ngày 05-08-2026 |
| iOS Simulator account sync re-run | Isolated user: UI sign-in/sign-out vẫn giữ local vault, upload/fresh-device download/Realtime/tombstone pass và remote cleanup verified ngày 09-08-2026 |
| Chrome Extension current profile | Owner manual smoke: Side Panel render sau local Roboto bundle, login Supabase, sync và session còn sau đóng/mở Chrome ngày 09-08-2026; không phải clean-profile/tamper evidence |
| iOS physical Ad Hoc | `1.1.0 (13)` chứa client Realtime, ký Distribution và upgrade-install pass trên iPhone 16 Pro ngày 05-08-2026; device query xác nhận build 13, auto-launch chờ user unlock |
| Android physical qua ADB Wi-Fi | Release-mode `1.1.0 (13)` ký lại bằng đúng debug certificate đang cài đã upgrade-install/launch pass ngày 05-08-2026, giữ app data; APK production-signing riêng đã verify nhưng không cài đè do signer khác |
| GitHub Preview 1.1.3 | Public pre-release [`v1.1.3-preview.1`](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.3-preview.1) từ commit `0a2105d1a7f7ecd92a537284977026fa94fcad34`; exact tag CI run [`31406851631`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31406851631) pass 8/8 và publish run [`31407810354`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31407810354) pass ngày 10-08-2026; public verifier độc lập [`31407979891`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31407979891) xác nhận đúng 9 asset, digest/checksum/manifest, Android signer pin, Debian, Windows PE32 và Chrome Extension package |
| Production Supabase | ADR-0020 + ADR-0021 đã deploy; remote contract pass 26/26; final audit 0 test account/user/Vault orphan; health pass |
| Backup Realtime rollout | Pre `supabase-20260805T154247Z` và post `supabase-20260805T161016Z`: checksum, full restore rehearsal và encrypted off-host copy pass |

## Khoảng trống đã biết

1. **Server trust:** backend/Vault root-key holder có thể giải mã TOTP. Cần bảo vệ
   operator access, backup key, audit và host như credential system.
2. **Ownership UX:** first signed-in user tự nhận các mã local chưa có owner.
   Không có UI chuyển ownership giữa hai Supabase user.
3. **Tombstone retention:** chưa có cleanup policy; giữ vô hạn để chống stale
   resurrection là an toàn nhưng cần retention design khi scale.
4. **Runtime coverage:** iOS Simulator đã pass account-sync + private Realtime;
   Android physical mới có install/launch evidence, chưa chạy isolated
   account-sync acceptance; Linux/Web và physical multi-device runtime cũng
   chưa có evidence tương đương. Background vẫn chờ app resume vì OS có thể
   suspend WebSocket.
5. **Phát hành:** Android signed APK, Windows x64 installer và Linux amd64 Debian
   package đã có trên GitHub Preview hiện tại. Windows/Linux vẫn unsigned; iOS/macOS
   chưa có GitHub binary và toàn bộ app-store rollout vẫn để sau.
6. **Release inputs:** store signing/notarization, SMTP, public privacy/support URL
   và external alert destination vẫn để sau.
7. **Chrome Extension:** owner cho phép ZIP vào GitHub Preview dưới disclosure
   `owner-waived`; current-profile render/login/sync/session smoke đã có, nhưng
   còn Chrome clean-profile restart/tamper và cross-device Side Panel runtime với
   isolated user. Không dùng evidence này để gọi extension production-ready hoặc
   Chrome Web Store ready; bộ icon HyperZ 16/32/48/128 đã có trong extension
   package. Source/package mới đã sửa incomplete fallback catalog nhưng console
   sau **Reload** chưa có runtime evidence do trang nội bộ Extension không cho
   automation truy cập; ngoài ra vẫn cần privacy/support URL, review độc lập,
   screenshot/promo assets và store review.
8. **Provider logo:** full catalog tăng khoảng 28,5 MB raw cho mọi artifact và
   mở rộng trademark review surface. Repository upstream dùng MIT nhưng không có
   provenance/license riêng cho từng brand mark; release phải giữ pin/NOTICE,
   chỉ dùng để nhận diện và xử lý takedown nếu có.

## Gate canonical

    scripts/agent/check.sh docs
    scripts/agent/check.sh quick
    scripts/agent/check.sh app
    scripts/agent/check.sh backend
    scripts/agent/check.sh release
    scripts/agent/check.sh infra
    scripts/agent/check.sh full
