# ADR-0012: Device-specific DEK wrap bằng HPKE và membership proof

- Trạng thái: Đã chấp nhận
- Ngày: 2026-07-19
- Owner: canhvx
- Thay thế:
- Bị thay thế bởi:

## Bối cảnh

E2EE v1 dùng một DEK cho current encrypted snapshot. Backend giữ DEK được wrap
bằng recovery key `HA1`; mỗi native client đã recovery giữ DEK plaintext trong
platform secure storage. Xoay DEK thu hồi khả năng decrypt current snapshot của
thiết bị chỉ giữ key cũ, nhưng đồng thời buộc mọi thiết bị còn lại nhập recovery
key mới. Device registry hiện chỉ thu hồi Supabase auth session, không phân phối
DEK mới riêng cho các thiết bị còn tin cậy.

Một session attacker không có DEK không được phép thêm public key rồi khiến client
tin cậy tự động wrap DEK cho key đó. Backend không biết DEK nên không thể tự xác
minh một device wrap hay proof E2EE.

RFC 9180 định nghĩa HPKE và official vector cho
DHKEM(X25519, HKDF-SHA256)/HKDF-SHA256/AES-GCM. Google Tink có HPKE nhưng không có
Dart target; đưa Java/C++/Objective-C bridge riêng vào năm native platform sẽ tạo
nhiều implementation/storage boundary hơn protocol tối thiểu hiện tại.

## Quyết định đề xuất

### Primitive

- Device key pair là X25519 256-bit, riêng theo Supabase user và installation.
  Private key cùng random binding secret 256-bit nằm trong platform secure
  storage; public key mới được gửi backend.
- DEK wrap dùng HPKE Base mode, one-shot sequence zero, suite cố định:
  `DHKEM(X25519, HKDF-SHA256)`, `HKDF-SHA256`, `AES-256-GCM`.
- `info` và AAD bind user ID, installation ID, opaque device-key ID, key
  generation và recipient public key. Mọi field dùng unsigned 32-bit
  length-prefix theo byte UTF-8/binary, không ghép delimiter text; vì vậy hai bộ
  identifier khác nhau không thể tạo cùng context do dấu phân cách. Unknown
  suite/version/generation fail closed.
- Envelope chỉ nhận canonical padded base64url với exact decoded length:
  encapsulated key 32 byte, ciphertext 32 byte và GCM tag 16 byte. Input
  oversized/non-canonical bị từ chối trước AEAD decrypt.
- Implementation tối thiểu phải khớp official RFC vector cho AES-128-GCM và
  official vector AES-256-GCM trước khi được inject. Không mở API multi-message,
  PSK hoặc authenticated mode.

### Membership và enrollment

- Encrypted snapshot được thêm monotonic `key_generation`, độc lập snapshot
  `revision`. Normal content sync giữ generation; DEK rotation tăng đúng một.
- Enrollment server tạo opaque device-key ID ở trạng thái pending. Client đang có
  current DEK tạo:
  1. HPKE wrap DEK cho device public key;
  2. membership proof HMAC-SHA256 bằng key được HKDF tách miền từ current DEK.
- Proof bind user/installation/device-key/public-key/generation. Backend chỉ lưu
  opaque proof; client có current DEK mới xác minh được. Device entry có proof lỗi
  không bao giờ được tự động nhận wrap trong rotation.
- Random binding secret chỉ chứng minh một installation đang resume đúng device
  record qua TLS; backend chỉ lưu hash. Nó không phải E2EE key, không thay
  membership proof và không được trả về API.

### Rotation và revoke

- Vault-key rotation publish atomically: encrypted snapshot, recovery-key wrapped
  DEK, generation mới, complete device wrap set và membership proof mới.
- Client phải validate proof của generation hiện tại trước khi đưa một device vào
  set mới. Không có chế độ “best effort” tự thêm record không verify.
- Cryptographic device revoke là cùng transaction rotation nhưng loại target,
  revoke device key và xóa auth session đã bind. Session revoke riêng hiện có vẫn
  tiếp tục là action nhẹ, không mang nhãn crypto revoke.
- Device còn tin cậy thấy generation mới sẽ thử HPKE unwrap bằng local private key,
  decrypt/validate snapshot rồi mới atomic thay DEK local. Nếu thiếu/invalid wrap,
  flow `HA1` recovery hiện tại vẫn là break-glass path.

### Ranh giới platform

- Chỉ Android, iOS, macOS, Windows và Linux. Web tiếp tục tắt cloud sync vì
  browser storage không có native secure-storage trust boundary.
- Đây không phải remote wipe, active screenshot prevention, crypto-erase backup
  lịch sử hoặc post-quantum protection.

## Phương án đã cân nhắc

### X25519 + HKDF + AES-GCM tự định nghĩa

Không chọn. Cùng primitive nhưng tự chọn transcript/KDF label dễ tạo lỗi domain
separation và không có interoperability vector chuẩn.

### Google Tink qua platform bridge

Chưa chọn. Tink không có Dart target; bridge riêng Android/Apple/Windows/Linux làm
khó giữ một serialized contract và tăng FFI/platform supply-chain surface. Có thể
xem lại nếu Tink/Dart hoặc một package HPKE được audit hỗ trợ đầy đủ target.

### Chỉ dùng symmetric device KEK

Không chọn. Trusted device cần truyền KEK bí mật cho device mới; server relay lại
đòi một public-key channel. HPKE giải quyết trực tiếp multi-recipient DEK wrap.

### Tự động tin mọi device đăng nhập hợp lệ

Không chọn. Compromise email/password/session nhưng chưa có DEK sẽ trở thành E2EE
compromise ngay khi một trusted client tự wrap DEK cho public key attacker.

## Hệ quả và rủi ro

### Tích cực

- DEK rotation không buộc mọi thiết bị còn tin cậy nhập recovery key mới.
- Session-only attacker không tạo được valid membership proof của current
  generation.
- Recovery key vẫn là root/break-glass độc lập server và password.

### Tiêu cực

- Schema/RPC và client state machine phức tạp hơn; rotation phải publish exact set
  atomically.
- X25519 private key export vẫn nằm trong secure-storage blob, chưa dùng
  hardware-non-exportable key API riêng từng OS.
- Local HPKE implementation dù khớp RFC vector vẫn cần independent security review
  trước khi tuyên bố stable production cryptographic device revoke.
- Source chủ động destroy object key và best-effort overwrite các buffer dẫn xuất
  sau mỗi operation. Dart VM/GC và platform implementation có thể tạo bản sao nên
  đây không phải cam kết zeroization phần cứng hoặc toàn bộ process memory.

### Threat/failure behavior

- Client có DEK đã compromise có thể tạo valid membership cho key attacker; control
  này không chống endpoint compromise sau unlock.
- Transport fail sau atomic rotation tạo trạng thái mơ hồ tương tự DEK rotation v1:
  phải giữ recovery key mới và inspect lại, không nâng metadata mù.
- Private key/device record mất hoặc corrupt không được tự tạo thay rồi coi là
  trusted; fallback là recovery key và explicit re-enrollment.
- Backup trước rotation vẫn decrypt được bằng generation cũ; không mô tả revoke là
  crypto-erase lịch sử.

## Dữ liệu, migration và rollback

Migration dự kiến additive:

1. thêm `key_generation default 1` vào encrypted snapshot;
2. tạo bảng device public key/membership metadata và device wrap;
3. bind nullable device-key ID vào registry session;
4. thêm RPC enrollment/list-wrap/atomic rotation; giữ RPC v1 normal publish;
5. backfill current row generation 1, không tạo device key giả;
6. client v2 enroll sau khi có DEK/recovery; client v1 tiếp tục dùng `HA1` wrap.

Owner đã chấp nhận ADR ngày 19-07-2026. Schema/RPC phải được khóa bằng PostgreSQL
contract và backup/rollback rehearsal trước production deploy. Rollback trước
runtime chỉ xóa source staged. Sau rollout, rollback client giữ recovery-key path,
không drop column/table cho tới khi đã audit không còn device v2 cần wrap.

## Xác minh bắt buộc

- Official RFC 9180 Base vector AES-128-GCM và official AES-256-GCM vector.
- Tamper/wrong user/installation/device/generation/private key fail closed.
- Delimiter-collision, non-canonical/oversized envelope và X25519 low-order key
  fail closed trước khi runtime integration.
- Secure-storage round-trip, corrupt record không tự replace, user isolation.
- PostgreSQL ephemeral + remote two-user/three-device contract.
- Native two-device runtime: enroll, rotate, surviving device auto-unwrap,
  excluded device fail và `HA1` recovery path còn hoạt động.
- Full backup/restore rehearsal và independent review trước stable release claim.

## Nguồn chuẩn

- [RFC 9180 — Hybrid Public Key Encryption](https://www.rfc-editor.org/rfc/rfc9180.html)
- [Official CFRG test vectors, pinned commit](https://github.com/cfrg/draft-irtf-cfrg-hpke/blob/5f503c564da00b0687b3de75f1dfbdfc4079ad31/test-vectors.json)
- [Google Tink hybrid encryption](https://developers.google.com/tink/hybrid)
- [Google Tink primitives by language](https://developers.google.com/tink/primitives-by-language)
