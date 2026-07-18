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
- Logout không xóa vault.
- App lock fail closed và relock theo lifecycle.
- Platform capability chặn plugin không hỗ trợ thay vì gọi rồi fallback không an toàn.

### Encrypted sync

- DEK và recovery key ngẫu nhiên 256-bit; AES-256-GCM qua package `cryptography`.
- Nonce random cho mỗi encryption; AAD bind user, revision, version và purpose.
- Recovery key hiển thị một lần, cần user xác nhận trước setup.
- DEK chỉ persist sau publish + read-after-write verification.
- Remote decrypt/validate hoàn tất trước atomic local replace.
- Optimistic revision + atomic RPC; conflict không delete cloud snapshot cũ.
- User ID được kiểm tra lại tại datasource để chặn cross-session race.
- Unknown format, tamper, sai user hoặc sai recovery key đều fail closed.

### Backend và operations

- `FORCE RLS`; owner SELECT; write chỉ qua RPC dùng `auth.uid()`.
- Public HTTPS; Studio có Basic Auth; database/Kong/Supavisor không expose trực tiếp.
- Secret/key server đã rotate trong đợt rebuild; JWT mới dùng ES256/JWKS.
- Health timer 5 phút; daily verified backup; encrypted off-host copy; full restore rehearsal.
- SSH chỉ public key, log level INFO; journal có retention/size limit.

### Build và supply chain

- Bootstrap chỉ nhận HTTPS Supabase origin và public `sb_publishable_*`/legacy
  `anon`; server key bị từ chối mà không xuất hiện trong error.
- Release bắt buộc HTTPS recovery URL và `ALLOW_INSECURE_PLAINTEXT_SYNC=false`.
- Android release manifest có INTERNET, cấm cleartext và tắt OS backup.
- Cả Debug/Release entitlement iOS/macOS đều khai báo Keychain Sharing; platform
  gate chống regression khi runner được regenerate.
- CI pin Gitleaks binary/checksum và scan toàn bộ Git history. Allowlist chỉ có
  fingerprint của public RFC 6238 vector, không dùng regex bỏ qua diện rộng.
- Flutter Web image dùng tar build context allowlist, Nginx pin digest, non-root,
  filesystem read-only, CSP theo Supabase origin và không access-log query. HTML
  không cache; source map và file môi trường làm image build fail.

## Recovery semantics

Supabase password reset không decrypt E2EE vault. Người dùng cần recovery key hoặc
một thiết bị còn DEK. Mất toàn bộ thiết bị và recovery key đồng nghĩa mất cloud
vault về mặt mật mã; support/admin không thể khôi phục plaintext.

Recovery key không được tự động copy, log, gửi analytics hoặc lưu SharedPreferences.
UI cho phép copy theo hành động rõ ràng; người dùng phải đưa key vào password manager
hoặc offline backup riêng.

## Destructive operations

- Cloud conflict phải hỏi rõ dùng cloud hay giữ local.
- Dùng cloud chỉ replace sau re-download đúng revision và decrypt/validate.
- Dọn Supabase data/volume yêu cầu full backup + checksum + restore note.
- Drop plaintext compatibility table là migration riêng, không nằm trong client rollout.
- Logout và disable sync không được xóa local vault hoặc remote snapshot.

## Logging và fixture

Không log/request fixture chứa:

- field `secretKey` với giá trị thật;
- full URI bắt đầu bằng `otpauth://`;
- recovery key `HA1-...`;
- JWT, refresh token, service-role key hoặc password;
- ciphertext kèm key material nếu không cần cho contract.

Test dùng placeholder `TEST_ONLY_*`. Shell operator script không chạy với `set -x`.
Không dùng command liệt kê toàn bộ process environment trong báo cáo.

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
3. Device revocation và key rotation chưa có trong envelope v1.
4. SMTP delivery tới mailbox thật và expired recovery link chưa được E2E test.
5. Signing key/certificate chưa được owner cung cấp trên môi trường build.
6. Browser local vault có trust model yếu hơn native dù cloud sync đã tắt.

## Báo cáo lỗ hổng

Không mở public issue chứa credential hoặc `otpauth` URI. Trước public release,
owner phải công bố một private security contact trong store metadata và privacy URL.
