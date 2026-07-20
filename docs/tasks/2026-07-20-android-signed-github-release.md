# Task: Phát hành Android signed APK qua GitHub

- Trạng thái: Đang thực hiện
- Bắt đầu: 2026-07-20
- Owner: Hyperz
- Issue hoặc ADR liên quan: ADR-0010

## Mục tiêu

Người dùng Android tải được APK release đã ký từ GitHub Preview, xác minh được
checksum, provenance và certificate fingerprint; mọi bản cập nhật GitHub tiếp
theo tiếp tục dùng cùng app signing key.

## Ngoài phạm vi

- Phát hành Google Play, tạo upload key riêng hoặc cấu hình Play App Signing.
- Đưa private key hay password signing vào repository, log hoặc artifact.
- Gọi preview là stable trước physical-device, support và legal gate.

## Acceptance criteria

- [x] App signing key ở ngoài repository, mode `0600`, có backup do owner giữ.
- [x] Gradle fail closed khi release signing thiếu và hỗ trợ path tuyệt đối/CI env.
- [x] Local harness build APK, xác minh chữ ký và khóa SHA-256 fingerprint.
- [x] Tag CI có source tạo signed APK/checksum mà không upload keystore hoặc debug
      symbol; bốn encrypted secrets đã có, còn chờ tag runtime evidence.
- [x] GitHub publisher/public verifier yêu cầu APK từ mọi tag mới nhưng vẫn đọc
      được ba preview lịch sử chỉ có Windows/Linux.
- [x] Signed APK pass install/runtime/upgrade gate trên Android emulator.

## Bằng chứng hiện tại

- Source path: `android/app/build.gradle.kts`, `.github/workflows/ci.yml`,
  `scripts/agent/github_preview_release.sh`.
- Cách tái hiện: release build dừng khi thiếu local properties hoặc CI env; signed
  harness pass khi credential đủ và certificate khớp pin.
- Test hiện có: Android debug compile và Android emulator local-vault/E2EE runtime.
- Giả định: key alias `hyper-authenticator` và fingerprint owner đã xác minh bằng
  `keytool -list -v` ngày 2026-07-20.

## Đánh giá rủi ro

- Lộ credential: cao nếu commit keystore/password; mitigated bằng ignore, mode,
  prompt ẩn, GitHub encrypted secret và artifact allowlist.
- Mất dữ liệu local: build không chạm data; install/upgrade test phải giữ vault.
- Mất dữ liệu cloud: không đổi schema hoặc sync contract.
- Migration: update Android chỉ hợp lệ khi certificate và application ID giữ nguyên.
- Rollback: chuyển release lỗi về draft; không đổi/xóa key đã dùng để phát hành.
- Tác động platform: Android; release manifest chung thêm APK/checksum.

## Kế hoạch

- [x] Pin public certificate fingerprint và thêm local signing harness.
- [x] Mở rộng CI/tag artifact và GitHub Preview publisher/verifier.
- [x] Chạy local signed build, signature verification và emulator upgrade.
- [x] Chạy full gate và secret history gate.
- [ ] Chạy tag CI với encrypted signing secrets đã cấu hình.
- [ ] Publish preview kế tiếp rồi tải lại không auth để xác minh.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| `keytool -list -v` do owner chạy | JKS RSA-2048, alias đúng, hạn tới 2053, fingerprint đã ghi nhận | 2026-07-20 |
| `stat` keystore | Đã hạ từ `0644` xuống `0600`; không đọc nội dung | 2026-07-20 |
| `flutter build apk --release` khi chưa có config | Fail closed tại Gradle, không sinh unsigned/debug-signed artifact | 2026-07-20 |
| `scripts/agent/check.sh full` | Pass docs/generated/format/analyze/platform/release/ops, 186 test và migration | 2026-07-20 |
| `scripts/agent/check_secrets.sh` | Pass 156 commit, không có leak | 2026-07-20 |
| `gh secret list` | Có đủ bốn Android signing secret; chỉ kiểm tra tên/thời gian, không đọc giá trị | 2026-07-20 |
| Public verifier trên `v1.1.0-preview.3` | Pass legacy exact 5 asset, tag CI, digest/checksum/manifest và desktop signature | 2026-07-20 |
| `build_android_release.sh .env ...` | Build APK 71,2 MB; đúng một V2 signer, SHA-256 khớp pin và checksum pass | 2026-07-20 |
| Pixel 10 Pro XL AVD API 37 signed runtime | Clean install/cold launch, Vietnamese semantics, process sống và crash buffer 0 | 2026-07-20 |
| Signed upgrade `1.1.0+10`→test `1.1.1+11` | Cùng signer, `firstInstallTime` và TEST_ONLY encrypted-vault fixture được giữ; AVD cleanup/restore `1.1.0+10` pass | 2026-07-20 |
| Post-runtime `scripts/agent/check.sh full` | Docs/generated/format/analyze/platform/release/ops và 186 test pass; migration gặp một transient container socket failure | 2026-07-20 |
| `scripts/supabase/test_encrypted_vault_migration.sh` retry | Pass ngay sau transient; container tạm cleanup đúng contract | 2026-07-20 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SECURITY.md`
- [x] `DEPLOYMENT.md`
- [x] `DEVELOPMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] ADR: không cần ADR mới; ADR-0010 đã quyết định signed Android được thêm sau
      credential/runtime gate.

## Bàn giao

Signed build/runtime/upgrade evidence, owner backup confirmation và GitHub encrypted
secrets đã có. Còn tag CI và public artifact verification.
