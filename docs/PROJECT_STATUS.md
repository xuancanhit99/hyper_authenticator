# Trạng thái dự án

Baseline được audit ngày **5 tháng 8 năm 2026** trên nhánh
`codex/minimal-e2ee`. Tên nhánh là lịch sử; source đã chuyển sang
account-managed automatic sync theo ADR-0020 và backend production đã được
migrate cùng ngày. Evidence phát hành được cập nhật ngày **9 tháng 8 năm 2026**.

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
  GitHub Preview với disclosure runtime acceptance bị waiver; clean-profile/
  tamper/cross-device Side Panel vẫn chưa có evidence và Chrome Web Store bị chặn.

## Đã triển khai trong source

### TOTP và local vault

- Parse/validate bounded `otpauth://totp`, Base32, SHA1/SHA256/SHA512, digits
  6–8 và period dương.
- Thêm bằng camera, ảnh QR hoặc nhập tay theo capability platform.
- Import standard `otpauth`/Google migration qua preview, exact dedupe và atomic
  copy-on-write append.
- Protected QR export yêu cầu fresh OS authentication, timeout/lifecycle cleanup
  và không persist raw QR payload.
- Tìm kiếm, sửa, xóa, sao chép mã và countdown theo period.
- `FlutterSecureStorage` giữ local vault v2 copy-on-write; logout không xóa mã.

### Account-managed automatic sync

- `SyncBloc` global nghe session restore/sign-in/sign-out và mutation của
  `AccountsBloc`; app resume và pull-to-refresh cũng yêu cầu sync.
- Mỗi remote account có stable UUID, revision CAS và deletion tombstone.
- Thiết bị mới chỉ cần đăng nhập để tải mã; không cần recovery credential.
- Local mutation commit trước; network lỗi không rollback local. Pending
  create/update/delete được suy ra từ secure ownership/revision/fingerprint
  metadata và retry ở lần sync sau.
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
- Auth còn email/password, đăng ký, session restore, quên/đổi mật khẩu.
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
- App Lock dùng local authentication khi platform hỗ trợ. Privacy Shield che nội
  dung ngoài foreground nhưng không phải active screenshot prevention.

## Data contract hiện tại

- Local vault: v2, không đổi.
- Secure sync metadata: `ha:cloud-sync:v1:metadata`.
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
| `flutter analyze` | Pass, 0 issue ngày 05-08-2026 |
| `flutter test` | Pass 231 test ngày 10-08-2026 |
| `scripts/supabase/test_account_sync_migration.sh` | Pass trên đúng `supabase/postgres:17.6.1.136`: Vault/RPC/CAS/tombstone và authorization probe đúng Realtime 2.102.3 |
| Full gate | `scripts/agent/check.sh full` pass ngày 10-08-2026: docs/codegen/format/analyze/platform, 231 Flutter test, migration/release/infra harness |
| iOS Simulator account sync | UI auth giữ local vault + upload/download/tombstone + remote-only upsert/delete qua Realtime pass; isolated user cleanup verified ngày 05-08-2026 |
| iOS Simulator account sync re-run | Isolated user: UI sign-in/sign-out vẫn giữ local vault, upload/fresh-device download/Realtime/tombstone pass và remote cleanup verified ngày 09-08-2026 |
| Chrome Extension current profile | Owner manual smoke: Side Panel render sau local Roboto bundle, login Supabase, sync và session còn sau đóng/mở Chrome ngày 09-08-2026; không phải clean-profile/tamper evidence |
| iOS physical Ad Hoc | `1.1.0 (13)` chứa client Realtime, ký Distribution và upgrade-install pass trên iPhone 16 Pro ngày 05-08-2026; device query xác nhận build 13, auto-launch chờ user unlock |
| Android physical qua ADB Wi-Fi | Release-mode `1.1.0 (13)` ký lại bằng đúng debug certificate đang cài đã upgrade-install/launch pass ngày 05-08-2026, giữ app data; APK production-signing riêng đã verify nhưng không cài đè do signer khác |
| GitHub Preview 1.1.2 | Public pre-release [`v1.1.2-preview.3`](https://github.com/xuancanhit99/hyper_authenticator/releases/tag/v1.1.2-preview.3) từ commit `b0a0d983ced69b405c5c3063a2ef90219772470e`; exact tag CI run [`31394148750`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31394148750) pass 8/8 và publish run [`31395060378`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31395060378) pass ngày 10-08-2026; public verifier độc lập [`31395351977`](https://github.com/xuancanhit99/hyper_authenticator/actions/runs/31395351977) xác nhận đúng 9 asset, digest/checksum/manifest, Android signer pin, Debian, Windows PE32 và Chrome Extension package |
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
   package đã có trên GitHub Preview 8. Windows/Linux vẫn unsigned; iOS/macOS
   chưa có GitHub binary và toàn bộ app-store rollout vẫn để sau.
6. **Release inputs:** store signing/notarization, SMTP, public privacy/support URL
   và external alert destination vẫn để sau.
7. **Chrome Extension:** owner cho phép ZIP vào GitHub Preview dưới disclosure
   `owner-waived`; current-profile render/login/sync/session smoke đã có, nhưng
   còn Chrome clean-profile restart/tamper và cross-device Side Panel runtime với
   isolated user. Không dùng evidence này để gọi extension production-ready hoặc
   Chrome Web Store ready; bộ icon HyperZ 16/32/48/128 đã có trong extension
   package, nhưng vẫn cần privacy/support URL, review độc lập, screenshot/promo
   assets và store review.

## Gate canonical

    scripts/agent/check.sh docs
    scripts/agent/check.sh quick
    scripts/agent/check.sh app
    scripts/agent/check.sh backend
    scripts/agent/check.sh release
    scripts/agent/check.sh infra
    scripts/agent/check.sh full
