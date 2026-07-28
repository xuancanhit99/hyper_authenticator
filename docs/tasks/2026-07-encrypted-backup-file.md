# Task: Backup file mã hóa portable

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-07-27
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0018

## Mục tiêu

Cho phép người dùng tạo và khôi phục một file backup portable được bảo vệ bằng
password, Argon2id và AES-256-GCM trên các platform Flutter đang hỗ trợ. Restore
phải xác thực toàn vẹn, preview trước khi thay dữ liệu và chỉ publish một
generation local-vault sau xác nhận phá hủy rõ ràng.

## Ngoài phạm vi

- Không dùng file backup làm cloud sync hoặc tự động tải file lên server.
- Không lưu, đồng bộ, log hoặc cung cấp cơ chế lấy lại password.
- Không import backup proprietary của ứng dụng khác; interoperability QR
  `otpauth`/Google Authenticator tiếp tục là luồng riêng.
- Không coi password yếu là tương đương recovery key ngẫu nhiên.

## Acceptance criteria

- [x] File v1 có envelope và plaintext schema version độc lập.
- [x] KDF là Argon2id v19 với parameter được persist và giới hạn trước khi chạy.
- [x] Cipher là AES-256-GCM; AAD bind purpose, version, KDF metadata, salt, cipher
      và nonce.
- [x] Wrong password, file bị sửa, future version, oversized input hoặc account
      lỗi đều fail closed và không mutate local vault.
- [x] Restore decrypt + validate toàn bộ, preview metadata không secret, yêu cầu
      xác nhận phá hủy rồi mới gọi một COW replacement commit.
- [x] Cancel file/password/save/preview không mutate vault và decrypted candidate
      bị xóa khi app rời foreground hoặc hết timeout.
- [x] Export/import đi qua system file/share contract trên Android, iOS, macOS,
      Windows, Linux và Web theo capability của plugin.
- [x] Không có raw secret, plaintext payload hoặc password trong log, BLoC
      `toString`, semantics, route hoặc persisted preference.

## Bằng chứng hiện tại

- Source path: `EncryptedBackupFileCodec` sở hữu bounded schema/crypto;
  `EncryptedBackupBloc` sở hữu candidate/timeout/restore orchestration;
  `SystemEncryptedBackupFileGateway` sở hữu system picker/share và Android
  `MainActivity` sở hữu native document save. Settings mở route
  `/encrypted-backup`.
- Restore chỉ gọi `AuthenticatorLocalDataSource.replaceAccounts()` sau decrypt,
  validate, preview và typed confirmation. Data source publish snapshot bằng
  copy-on-write generation rồi mới đổi commit marker.
- Codec/BLoC/widget regression bao phủ production KDF, tamper, wrong password,
  malformed/future/resource-bound input, cancel/timeout/lifecycle, picker-close
  race, single replacement và commit failure giữ snapshot active.
- Giả định: file do người dùng tự quản lý; app không thể khôi phục password bị
  quên và không thể ngăn người dùng sao chép file sang nơi kém an toàn.

## Đánh giá rủi ro

- Lộ credential: plaintext account/password tồn tại tạm trong process memory;
  file chỉ được ghi sau AEAD encryption. Dart `String` không bảo đảm zeroize.
- Mất dữ liệu local: restore là full replacement; preview và destructive
  confirmation bắt buộc. COW commit lỗi giữ generation active trước đó.
- Mất dữ liệu cloud: không tự gọi sync hoặc ghi Supabase; lần backup cloud thủ
  công sau restore có thể publish local snapshot mới theo conflict contract.
- Migration: không đổi local vault v2 hoặc Supabase schema; file format có version
  riêng và decoder v1 phải được giữ khi encoder tương lai nâng version/KDF.
- Rollback: revert feature/dependency/UI; file v1 đã phát hành vẫn cần decoder
  tương thích ở release sau.
- Tác động platform: thêm file-picker plugin và entitlement read/write do người
  dùng chọn trên macOS; cần build/test platform đại diện.

## Kế hoạch

- [x] Khóa schema/threat model bằng ADR và regression test.
- [x] Thêm codec bounded Argon2id + AES-256-GCM.
- [x] Thêm file gateway đa nền tảng và BLoC không phát tán secret.
- [x] Thêm export password confirmation, import password, preview và destructive
      confirmation.
- [x] Cập nhật canonical docs, dependency/platform contract.
- [x] Chạy focused test, `scripts/agent/check.sh full` và platform build.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `flutter analyze` | Pass, 0 diagnostic | 2026-07-27 |
| Focused codec/BLoC/widget test | Pass, 18 test | 2026-07-27 |
| `scripts/agent/check.sh full` | Pass, gồm 252 Flutter test và toàn bộ backend/release/infra contract | 2026-07-27 |
| `flutter build apk --debug` | Pass | 2026-07-27 |
| `flutter build web --release` | Pass; còn warning font CupertinoIcons có sẵn từ baseline | 2026-07-27 |
| `flutter build ios --simulator --debug` | Pass | 2026-07-27 |
| `scripts/agent/build.sh host` | Pass Android, Web và macOS unsigned compile | 2026-07-27 |
| `flutter build macos --debug` trực tiếp | Bị gate signing do entitlement user-selected file; unsigned compile ở harness pass | 2026-07-27 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `DATA_MODELS.md`
- [x] `SECURITY.md`
- [x] `TESTING_STRATEGY.md`
- [x] `ROADMAP.md`
- [x] ADR-0018

## Bàn giao

Đã triển khai portable `.hyauth` v1 mà không đổi local-vault v2, cloud envelope,
Supabase schema hoặc production data. File giữ stable ID, order và TOTP
semantics; restore là full replacement có preview và một atomic COW commit.

Rủi ro còn lại: Dart không bảo đảm zeroize `String`; Web có thể cấp phát browser
blob trước khi Dart kiểm tra size; iOS share sheet không thể chứng minh retention
lâu dài. Follow-up ngày 29-07 đã pass backup → clean profile → restore trên Android
AVD và iOS Simulator; vẫn chưa có rehearsal trên thiết bị thật hoặc packaged
desktop. Release sau phải tiếp tục decode v1 kể cả khi encoder nâng schema/KDF.
