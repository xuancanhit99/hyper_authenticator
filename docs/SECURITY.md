# Bảo mật

## Asset cần bảo vệ

- TOTP `secretKey`, full `otpauth` URI và generated OTP.
- E2EE DEK và recovery key.
- Supabase session/refresh token.
- Service-role key, database password, SMTP credential, SSH key và signing key.
- Local vault, database/Storage backup và decrypted restore artifact.

Publishable key không phải secret nhưng chỉ được dùng ở client; service-role key
không bao giờ được đặt trong Flutter `.env`, asset, build log hoặc binary.

## Trust boundary

- Native secure storage bảo vệ local vault/DEK khi OS profile chưa unlock.
- Local authentication là UX/access gate; không chống thiết bị đã unlock và bị
  compromise hoàn toàn.
- Supabase Auth xác định identity; RLS xác định authorization.
- AES-256-GCM làm backend-blind với TOTP payload nếu client/recovery key an toàn.
- TLS bảo vệ transport, không thay thế E2EE.
- Web/browser profile không được xem tương đương Keychain/Keystore; Web E2EE sync tắt.

## Control đã triển khai

### Local

- Versioned copy-on-write vault; commit marker ghi sau cùng; rollback generation.
- Compaction giữ active và rollback generation.
- TOTP validation tập trung; không log barcode payload/secret.
- `AccountAddSuccess` và `AccountUpdateSuccess` không mang account/secret trong
  BLoC state; UI chỉ dùng tín hiệu operation-specific tương ứng để hoàn tất
  navigation, không suy diễn mutation thành công từ một lần reload danh sách.
- Update success/failure mang opaque in-memory token để route chỉ nhận đúng request
  đã phát. `AddAccountRequested`, `UpdateAccountRequested` và update result
  override string representation, không đưa issuer, account identity, secret hoặc
  token thật vào transition/crash log; equality semantics vẫn giữ nguyên.
- `AuthenticatorAccount`, `AddAccountParams` và `UpdateAccountParams` cũng redact
  string representation. `toJson` vẫn chứa secret theo persisted contract và chỉ
  được gọi trong storage/encryption path, không dùng làm log payload.
- Logout không xóa vault.
- App lock fail closed và relock theo lifecycle.
- Root `PrivacyShield` che toàn bộ router ở mọi lifecycle khác `resumed`, bỏ
  keyboard focus, dừng ticker và loại cây nội dung khỏi semantics trong khi che.
  Lớp che dùng Material 3 static, có opaque base + gradient không sample route,
  responsive ở viewport hẹp/text scale lớn và chỉ công khai một semantics label
  an toàn. Nó không dispose hoặc mutate vault/state bên dưới.
- Platform capability chặn plugin không hỗ trợ thay vì gọi rồi fallback không an toàn.
- Windows đóng băng AppData identity tương thích `1.0.0+9`. Layout migrator chạy
  trước DI, chỉ copy atomic allowlist, không theo symlink/không xóa nguồn và dừng
  bootstrap nếu hai vault khác nhau.

### Encrypted sync

- DEK và recovery key ngẫu nhiên 256-bit; AES-256-GCM qua package `cryptography`.
- Nonce random cho mỗi encryption; AAD bind user, revision, version và purpose.
- Recovery key hiển thị một lần, cần user xác nhận trước setup.
- DEK chỉ persist sau publish + read-after-write verification.
- Remote decrypt/validate hoàn tất trước atomic local replace.
- Optimistic revision + atomic RPC; conflict không delete cloud snapshot cũ.
- User ID được kiểm tra lại tại datasource để chặn cross-session race.
- Unknown format, tamper, sai user hoặc sai recovery key đều fail closed.
- Recovery key có thể được xoay bằng re-wrap cùng DEK và atomic revision mới. Key
  cũ không mở snapshot hiện tại sau commit; conflict không thay key đang dùng.
- Verification lỗi sau publish được xem là trạng thái mơ hồ: user phải giữ key mới,
  client không tự nâng revision metadata. Rotation không revoke thiết bị đã có DEK
  và không vô hiệu key cũ đối với encrypted backup lịch sử.
- Vault-key rotation sinh DEK + recovery key mới, re-encrypt current snapshot và
  atomic publish cả ciphertext/wrapped key. DEK local chỉ thay sau remote verify;
  cancel/conflict giữ key cũ. Trước khi tạo next-generation wrap, client dùng DEK
  hiện tại để verify current-generation wrap/proof của **mọi** active device và
  fail closed nếu một entry thiếu, stale hoặc giả. Generic rotation cấp wrap mới
  cho toàn bộ tập đã verify; Settings chưa có per-device cryptographic exclusion.
  Surviving device có private key sẽ verify exact HPKE wrap/proof rồi tự thay DEK;
  device không có wrap hoặc mất private key phải dùng HA1.
- Publish/verify/secure-storage failure sau request được coi là mơ hồ; client giữ
  last-seen revision cũ và hướng user giữ recovery key mới thay vì retry mù.
- Settings cho phép một phiên tin cậy gọi Supabase `SignOutScope.others`: phiên
  hiện tại và local vault/DEK được giữ, refresh token của mọi phiên khác bị thu hồi.
- Device registry bind server-side với JWT current session. Client không gửi
  `user_id`/`session_id`; list không trả session ID, IP hoặc user agent. Targeted
  revoke cấm current session và xóa đúng owned `auth.sessions` row. Installation
  UUID/label chỉ là pseudonymous display metadata, không phải authenticator.
- RLS SELECT và RPC publish còn yêu cầu JWT `session_id` khớp row còn hiệu lực
  trong `auth.sessions` của `auth.uid()`. Vì vậy access JWT đã cấp cho session vừa
  revoke vẫn có thể còn hợp lệ về chữ ký/thời hạn nhưng không đọc hoặc ghi được
  encrypted vault.

### Backend và operations

- `FORCE RLS`; owner + active-session SELECT; write chỉ qua RPC kiểm tra
  `auth.uid()` và active `session_id`.
- Device registry cũng bật + force RLS, không grant direct client table access;
  register/list/revoke là `SECURITY DEFINER` RPC với active-session guard.
- Public HTTPS; Studio có Basic Auth; database/Kong/Supavisor không expose trực tiếp.
- Secret/key server đã rotate trong đợt rebuild; JWT mới dùng ES256/JWKS.
- Health timer 5 phút; daily verified backup; encrypted off-host copy; scheduled
  restore drill với freshness evidence và full security probe.
- SSH chỉ public key, log level INFO; journal có retention/size limit.

### Build và supply chain

- Bootstrap chỉ nhận HTTPS Supabase origin và public `sb_publishable_*`/legacy
  `anon`; server key bị từ chối mà không xuất hiện trong error.
- Release bắt buộc HTTPS recovery URL. `ALLOW_INSECURE_PLAINTEXT_SYNC` chỉ còn là
  poison sentinel; giá trị `true` bị từ chối ở mọi build, không chỉ Release.
- Android release manifest có INTERNET, cấm cleartext và tắt OS backup.
- Cả Debug/Release entitlement iOS/macOS đều khai báo Keychain Sharing; platform
  gate chống regression khi runner được regenerate.
- CI pin Gitleaks binary/checksum và scan toàn bộ Git history. Allowlist chỉ có
  fingerprint của public RFC 6238 vector, không dùng regex bỏ qua diện rộng.
- Flutter Web image dùng tar build context allowlist, Nginx pin digest, non-root,
  filesystem read-only, CSP theo Supabase origin và không access-log query. HTML
  không cache; source map và file môi trường làm image build fail.
- Windows installer toolchain pin NSIS 3.12 archive SHA-256 và xác minh compiler
  version. Builder từ chối env/source-map/debug artifact; unsigned candidate có
  checksum LF portable và không được mô tả là signed release.
- Android app signing key nằm ngoài repository, file mode `0600`; source chỉ pin
  public certificate SHA-256. Local/GitHub configuration dùng prompt ẩn, CI chỉ
  khôi phục keystore vào runner tạm và xóa ở bước `always()`. Gradle/build harness
  fail closed khi thiếu credential hoặc APK signer không khớp pin.
- GitHub Preview harness chỉ nhận artifact từ successful CI run của chính tag,
  kiểm tra version/checksum/allowlist và tạo manifest tổng. Ba preview lịch sử giữ
  Windows/Linux; mọi tag mới bắt buộc thêm signed Android APK/checksum. Publish cần
  confirmation rõ ràng; release luôn mang pre-release flag và cảnh báo platform.
- Post-publish verifier không gửi Authorization, đối chiếu public tag/commit/tag-CI,
  exact 5/7 asset theo contract, GitHub SHA-256 digest, checksum/manifest, Android
  signer fingerprint và file signature desktop. Gate
  lỗi yêu cầu publisher chuyển release về draft thay vì để public trạng thái mơ hồ.
- Web live rollback harness chỉ nhận image pin semantic-version + commit hex và
  exact JS hash. Nó không source/in deployment env, preflight shadow trước mutation,
  atomic đổi riêng `WEB_IMAGE`, giữ snapshot 0600 và auto-restore original image
  khi verification fail. Evidence không chứa `SUPABASE_URL` hoặc credential.

## Recovery semantics

Supabase password reset không decrypt E2EE vault. Người dùng cần recovery key hoặc
một thiết bị còn DEK. Mất toàn bộ thiết bị và recovery key đồng nghĩa mất cloud
vault về mặt mật mã; support/admin không thể khôi phục plaintext.

Targeted device-session revoke chỉ cắt Supabase authorization và hủy refresh
session. Nó không remote-wipe local TOTP, không làm thiết bị quên DEK đã giữ và
không vô hiệu encrypted backup cũ. Xoay vault key bằng flow generic hiện tại cũng
không loại target: mọi active device key có proof hợp lệ đều nhận wrap mới. Backend
có atomic exclusion contract, nhưng Settings/client flow chưa cung cấp lựa chọn đó;
vì vậy không được mô tả chuỗi “rotate rồi revoke” như cryptographic device revoke.

Recovery key không được tự động copy, log, gửi analytics hoặc lưu SharedPreferences.
UI cho phép copy theo hành động rõ ràng; người dùng phải đưa key vào password manager
hoặc offline backup riêng. Raw key nhìn thấy trên màn hình nhưng bị loại khỏi
semantics tree tự động để assistive technology không tự đọc credential; nút copy
có accessible name nhưng không chứa key. Recovery import dùng field obscured, tắt
autocorrect/suggestion và vẫn hỗ trợ keyboard submit.

Copy là hành động chủ động đưa key vào clipboard do OS quản lý. App không log hoặc
persist clipboard content; người dùng phải xóa clipboard theo threat model của
thiết bị nếu clipboard history/sync đang bật.

## Screenshot và screen capture

**Đã triển khai:** lifecycle privacy shield giảm rò rỉ TOTP, recovery key và
identity qua app switcher/background snapshot trên toàn bộ Flutter target. Sau
bootstrap, mọi lifecycle signal `inactive`, `hidden`, `paused` và `detached` đều
che nội dung; `resumed` mới gỡ shield. Widget regression xác minh overlay opaque,
bỏ focus, chặn interaction và không để nội dung bên dưới xuất hiện trong semantics
tree. Overlay dùng opaque base cùng gradient đã alpha-blend, branding Material 3
static, không blur/animation/ticker; regression bao phủ light/dark theme, viewport
320 px và text scale 200%. Initial `detached` trước lifecycle signal không tự che
vì Linux headless và một số desktop runtime không phát `resumed`; CI runtime khóa
compatibility này.

**Khoảng trống đã biết:** shield không ngăn active screenshot, screen recording,
screen sharing khi app vẫn `resumed`, camera ngoài chụp màn hình hoặc phần mềm đã
compromise OS profile. Project chưa bật native capture-blocking vì support và UX
khác nhau theo platform:

- Android có `FLAG_SECURE` để loại activity khỏi screenshot/non-secure display,
  nhưng chưa bật và chưa có runtime gate trên thiết bị đại diện.
- iOS API đã đối chiếu chỉ phát notification sau screenshot và báo trạng thái
  screen capture; project chưa xác minh control chính thức có thể chặn screenshot.
- Windows có `WDA_EXCLUDEFROMCAPTURE` từ Windows 10 version 2004 nhưng Microsoft
  mô tả đây là best-effort window-content protection, không phải DRM; chưa bật.
- `NSWindow.SharingType.none` là legacy constant macOS không còn dùng; Linux phụ
  thuộc compositor và Web phụ thuộc browser/OS, nên chưa có control portable được
  xác minh.

Không tuyên bố screenshot prevention cho platform nào cho tới khi product chốt
việc chặn capture/casting, native implementation có failure telemetry không chứa
secret và runtime test pass trên platform đó.

Event/state BLoC có recovery key vẫn giữ equality semantics nhưng override string
representation thành `[REDACTED]`, phòng transition/crash logger vô tình ghi key.
Các auth event/state chứa email, password hoặc user identity cũng redact string
representation; equality vẫn hoạt động nhưng transition log không lộ credential/PII.

## Device-specific key protocol — **Đã deploy server và phát hành trong GitHub Preview**

ADR-0012 đề xuất HPKE Base
DHKEM(X25519, HKDF-SHA256)/HKDF-SHA256/AES-256-GCM cho per-device DEK wrap.
Implementation đã có DI, enrollment/recovery/publish-v2/atomic-rotation call site
và được khóa bằng official RFC vector, wrong-context/tamper/low-order-key test cùng
secure-storage corrupt-record test. Context dùng length-prefix thay delimiter;
envelope bắt buộc canonical exact
length để từ chối payload oversized trước decrypt. Derived HPKE key object được
destroy và buffer tạm được overwrite best-effort; Dart VM/GC không bảo đảm mọi
bản sao trong process đã zeroize.

Device private key và binding secret là credential. Chúng không được log, đưa vào
SharedPreferences, analytics, fixture thật hoặc server response. Membership proof
được domain-separate từ current DEK để session attacker không có DEK không khiến
trusted client tự động cấp wrap. Server còn so khớp vault membership verifier
HMAC dẫn xuất từ DEK; verifier nằm trong bảng `private`, không xuất hiện trong
snapshot SELECT hoặc device RPC. Additive migration/RPC chỉ công khai public
key, SHA-256 binding-secret hash và opaque per-device proof qua controlled RPC;
direct table access bị revoke/force RLS. V2 publish yêu cầu active device binding;
client phải verify wrap + proof của toàn bộ active set bằng current DEK trước khi
tạo bất kỳ next-generation wrap nào. Rotation backend thay snapshot + verifier +
exact wrap set và có thể revoke excluded session trong một transaction; generic
client hiện gửi exclusion rỗng. Lost local device key chỉ được thay bằng đúng DEK
verifier dẫn xuất từ HA1; key/session cũ bị revoke atomically.

Migration hardening cuối cùng giới hạn legacy publish RPC ở initial revision 1.
Mọi update phải dùng RPC v2; hàm này khóa exact snapshot row bằng `FOR UPDATE`, rồi
kiểm tra revision/generation/protocol `1` và active device binding trên state đã
khóa. Protocol `0` bị từ chối trước mutation, nên confirm protocol và publish
không còn cửa sổ TOCTOU. Production cùng Linux, Android AVD và iOS Simulator
runtime của device-wrap cơ sở đã pass; two-session runtime còn xác minh survivor
tự unwrap generation mới. Chưa qua independent security review hoặc physical
two-device test.

## Destructive operations

- Cloud conflict phải hỏi rõ dùng cloud hay giữ local.
- Dùng cloud chỉ replace sau re-download đúng revision và decrypt/validate.
- Dọn Supabase data/volume yêu cầu full backup + checksum + restore note.
- Plaintext client stack đã bị xóa. Migration loại bỏ cuối cùng chỉ drop
  `public.synced_accounts` sau `ACCESS EXCLUSIVE` lock khi bảng rỗng; còn row thì
  abort nguyên transaction với `plaintext_legacy_rows_present`, không log content
  và không dùng `CASCADE`. Migration đặt `row_security=off`, nên operator thiếu
  `BYPASSRLS` fail closed thay vì nhận count bị policy lọc. Production apply ngày 22-07 đã dùng fresh backup,
  off-host copy và zero-row preflight; mọi future restore/rollout vẫn phải lặp
  các gate này. Rollback không bật lại plaintext trong client mới.
- Logout và disable sync không được xóa local vault hoặc remote snapshot.
- Device integration local-vault suite chỉ chạy trên Android emulator/iOS Simulator,
  cần opt-in rõ ràng và luôn cleanup fixture; runner từ chối máy thật/macOS để tránh
  thay vault người dùng.
- Linux local-vault suite chỉ chạy khi `CI=true`, dùng XDG sandbox mode 0700,
  private D-Bus Secret Service và Xvfb; nó probe keyring trước test rồi xóa sandbox
  bằng trap, không dùng keyring hoặc local vault của desktop user.
- Debian package không có maintainer script xóa user data. Package smoke mutate
  Ubuntu container tạm, kiểm tra `/` giữ mode 0755 và XDG sentinel còn nguyên sau
  metadata upgrade/remove; historical-release vault migration vẫn là gate riêng.
- Distro matrix chỉ mutate bốn container Ubuntu/Debian pin digest trên hosted
  Linux runner, dùng XDG mode 0700, package-provided `gnome-keyring`, Xvfb và
  Weston headless; không mount home, keyring hoặc vault người dùng. Package khai
  báo explicit EGL/GLES/GL loader và Secret Service provider để không phụ thuộc
  dependency tình cờ của distro/desktop.
- Windows NSIS uninstaller chỉ xóa program directory/shortcut/registry metadata,
  không xóa AppData. Hosted-runner smoke kiểm tra sentinel còn nguyên qua metadata
  upgrade và uninstall; guard từ chối workstation/self-hosted runner. Historical
  harness cũng chỉ nhận runner tạm, build source pin `1.0.0+9`, ghi vault bằng
  plugin 3.1.2 rồi yêu cầu current app đọc/publish COW v2 và cleanup. Physical
  device/Windows Hello vẫn là gate riêng.
- Web rollback drill mutate container stateless, không truy cập browser local vault.
  EXIT trap khôi phục current image nhưng không bảo vệ được `SIGKILL`, host/Docker
  crash; snapshot env/current image phải được giữ cho manual recovery.
- Authenticated Linux E2EE gate chỉ nhận service-role key trong parent operator
  shell từ file 0600 ngoài repository. Key dùng qua temp header 0600, không export
  sang Docker/Flutter và không lưu ở GitHub Actions. Container chỉ nhận credential
  của isolated `.invalid` user, chạy trong XDG/private-keyring sandbox; operator
  luôn xóa user, dựa vào FK CASCADE để xóa vault row và probe admin 404.
- Scheduled restore runner chỉ chọn backup basename canonical, từ chối backup quá
  hạn/symlink, khóa cùng daily backup và restore vào database tạm có prefix cố định.
  Evidence mode 0600 chỉ được atomic replace sau pass; failure giữ evidence cũ để
  health gate phát hiện. Systemd giới hạn timeout, CPU/IO priority và writable path.

## Logging và fixture

Không log/request fixture chứa:

- field `secretKey` với giá trị thật;
- full URI bắt đầu bằng `otpauth://`;
- recovery key `HA1-...`;
- JWT, refresh token, service-role key hoặc password;
- ciphertext kèm key material nếu không cần cho contract.

Test dùng placeholder `TEST_ONLY_*`. Shell operator script không chạy với `set -x`.
Không dùng command liệt kê toàn bộ process environment trong báo cáo.

Auth load gate chỉ gọi health endpoint bằng public publishable key; không tạo user,
session hoặc request payload, không in key và chỉ lưu status/timing breakdown cùng
UTC timestamp trong temp directory mode 0700 rồi cleanup bằng trap. NPM timing log
chỉ nhận exact Auth health route và allowlist tám field status/request/upstream
timing; không ghi client IP, URI, header, User-Agent, payload hoặc credential.

NPM production không còn giữ DB password literal trong Compose, `.env` hoặc
container `Config.Env`. Runtime dùng ba file-secret mount; host secret directory
giữ mode `0700`, hai secret file `0400`, còn Compose, `.env` và application
`keys.json` giữ `0600`. Runtime NPM/MariaDB được pin exact digest thay vì floating
tag. Backup NPM chứa database/config/certificate và secret file nên là sensitive
artifact, phải giữ directory/file `0700`/`0600` hoặc chặt hơn và không đưa vào
repository hoặc CI.

**Đã triển khai:** backup và route-matrix harness resolve database
credential bên trong MariaDB container từ `MYSQL_PASSWORD`/`MARIADB_PASSWORD`
hoặc biến `*_PASSWORD_FILE`. File path phải absolute, readable, là regular file
không phải symlink; thiếu hoặc sai credential fail im lặng trước database command.
Password không đi qua Docker CLI argument hoặc host process environment. Helper
giữ tương thích cả rollback backup dạng env cũ và production file-secret.

**Đã triển khai:** production đã chuyển DB credential sang Docker file secrets
bằng renderer fail-closed, read-only preparation và deploy/rollback transaction.
Fresh backup + restore, exact canary, DB-first/app recreate, no-plaintext inspect,
post-backup restore và public/runtime gate đều pass. Không được rotate credential,
xóa rollback artifact hoặc recreate database/app lần tiếp theo trước fresh backup,
restore, exact canary, checksum/drift guard và pre-route pass.

Bundle file-secret là sensitive: original/candidate, `.env`, resolved input và
secret không được log/commit/copy sang CI. Renderer chỉ tạo output mới, giữ bundle
0700, Compose/`.env` 0600 và secret 0400; mismatch hoặc partial file-secret config
fail mà không in credential. Deploy recreate DB trước app, xác minh không còn
plaintext password trong `Config.Env`, exact mounts và chỉ xóa secret sau khi exact
rollback runtime/route đã pass. Bundle quá 7.200 giây fail trước mutation để tránh
rollback bằng database snapshot đã bỏ sót thay đổi NPM mới.

NPM upgrade rehearsal chỉ extract sensitive app/certificate vào sandbox 0700,
dùng password ngẫu nhiên qua env file 0600 và Docker network `--internal` không
publish port. Cleanup xóa container kèm anonymous volume, network và sandbox;
target canary không được kết nối public hoặc mutate database production.

NPM route matrix lấy hostname trực tiếp từ database nhưng chỉ log 12 ký tự SHA-256
khi fail; critical/exception manifest production mode 0600 và nằm ngoài repository.
Exception chỉ nhận exact 5xx + hash đã audit, không chứa URL và không cho phép 000/
status khác. Maintenance bundle có original/candidate Compose chứa DB password
literal nên bắt buộc directory/file 0700/0600; resolved Compose temp bị xóa trước
khi publish bundle.

Production deployment harness chỉ nhận checksum bundle đã byte-match Compose hiện
tại, exact image ID/digest và explicit mutation confirmation. Nó chỉ recreate NPM
app service; MariaDB/network/volume không bị dừng hoặc xóa. Post-gate khóa runtime
version, image, internal API, Nginx syntax và full redacted route matrix; failure
kích hoạt rollback exact Compose/image. Rollback Compose chứa credential nên giữ
mode 0600. Hourly route service không inject credential, dùng `ProtectSystem`,
`PrivateTmp`, `NoNewPrivileges` và chỉ journal status cùng hash domain.

## Dependency và asset supply chain

- Lockfile được commit; CI pin Flutter và secret scanner checksum.
- Direct package được review bằng `flutter pub outdated`; advisory flag phải bằng false.
- Averta thương mại và 1.047 logo dịch vụ không rõ provenance đã bị loại.
- Release chỉ bundle branding do owner kiểm soát và icon Material/Cupertino từ Flutter.
- Thêm asset bên thứ ba mới cần source URL, exact license, attribution/NOTICE và
  trademark-purpose review trong cùng commit.

## Khoảng trống đã biết

1. Chưa có external alert channel/SIEM; systemd failure hiện chỉ vào journal.
2. Chưa có independent cryptographic/security review.
3. Đã có device registry, bulk/targeted auth-session revoke và server-side
   active-session guard. Device-specific wrapped key đã deploy và có runtime trên
   Linux/Android/iOS, nhưng chưa có physical two-device/independent review. Backend
   hỗ trợ exact-set exclusion trong atomic rotation; Settings/generic client chưa
   cung cấp per-device cryptographic exclusion và hiện giữ mọi active device có proof
   hợp lệ. Backup cũ vẫn decrypt được bằng key material cũ.
4. SMTP delivery tới mailbox thật và expired recovery link chưa được E2E test.
5. Android app-signing key đã được owner backup và đưa vào GitHub Actions encrypted
   secrets; signed APK/tag CI/public signer verification đều pass. Apple và Windows
   signing certificate vẫn chưa có, nên desktop GitHub Preview còn
   Gatekeeper/SmartScreen/package-signature risk đã công bố.
6. Browser local vault có trust model yếu hơn native dù cloud sync đã tắt.
7. Background/app-switcher đã có lifecycle shield; active screenshot/recording/
   sharing khi app foreground vẫn là accepted risk chưa có platform runtime gate.

## Báo cáo lỗ hổng

Không mở public issue chứa credential hoặc `otpauth` URI. Báo cáo lỗ hổng bằng
[GitHub private security advisory](https://github.com/xuancanhit99/hyper_authenticator/security/advisories/new).
Kênh support và privacy URL công khai vẫn phải hoàn tất trước stable/store release.
