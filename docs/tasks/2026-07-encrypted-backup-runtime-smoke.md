# Task: Runtime smoke cho backup file mã hóa

- Trạng thái: Hoàn thành
- Bắt đầu: 2026-07-29
- Owner: HyperZ
- Issue hoặc ADR liên quan: ADR-0018

## Mục tiêu

Chứng minh luồng `.hyauth` đi qua system share/file picker thật trên Android AVD
và iOS Simulator, đồng thời restore từ một local vault sạch mà không làm lộ
credential hoặc chạm dữ liệu trên thiết bị thật.

## Ngoài phạm vi

- Không chạy destructive harness trên iPhone/Android vật lý hoặc macOS vault của
  owner.
- Không upload file test lên Drive, iCloud hoặc dịch vụ bên thứ ba; chỉ dùng
  storage local của emulator/simulator.
- Không coi simulator evidence là physical-device hoặc store-release evidence.

## Acceptance criteria

- [x] Guard từ chối thiết bị thật, target macOS, phase/confirmation/config lỗi.
- [x] Android AVD và iOS Simulator pass baseline secure-storage/local-vault smoke.
- [x] System save/share cancel không mutate vault; system save tạo file encrypted.
- [x] System picker đọc file tampered và sai password nhưng không mutate vault.
- [x] Preview cancel giữ vault sạch; confirm gọi atomic restore và round-trip đủ
      stable ID/order/TOTP semantics.
- [x] Cleanup xóa test vault, secure-storage probe và preference dù test fail.
- [x] Evidence/log không chứa raw TOTP secret, password hoặc full `otpauth`.

## Bằng chứng hiện tại

- Source path: `EncryptedBackupPage`, `SystemEncryptedBackupFileGateway`,
  Android `MainActivity`, `SystemUiInteractionGuard`,
  `EncryptedBackupFileCodec` và `AuthenticatorRepository.replaceAccounts()`.
- Cách tái hiện: guarded two-phase runner
  `scripts/agent/encrypted_backup_device_smoke.sh` với operator checkpoint được
  mô tả trong `docs/DEVELOPMENT.md`.
- Regression mới khóa Android native saved/cancelled mapping, system UI guard,
  lifecycle paused → resumed trước password dialog và barrier không dismiss
  restore password.
- Android 17/API 37.1 AVD và iOS 26.3 Simulator đều pass full export/restore;
  file được lưu local Downloads/On My iPhone rồi cleanup.

## Đánh giá rủi ro

- Lộ credential: chỉ dùng constant `TEST_ONLY`; phase log không in secret,
  password, OTP, file content hoặc account identity.
- Mất dữ liệu local: runner chỉ nhận Android emulator/iOS Simulator và cần
  `--allow-test-vault-reset`; cleanup chạy trong `finally`.
- Mất dữ liệu cloud: test không login, gọi sync hoặc publish snapshot.
- Migration: không đổi local vault, `.hyauth` v1 hoặc cloud schema. Android save
  boundary đổi từ share sheet sang native document picker.
- Rollback: revert MethodChannel/guard/runner/test/docs; không có production-data
  rollback. File v1 vẫn tương thích.
- Tác động platform: system sheet cần operator action. AVD owner có PIN được giữ
  nguyên; runtime dùng AVD tạm, sau test xóa AVD nhưng giữ shared system image.
- Gap phát hiện đã sửa: Android share sheet không có local save target; app-lock
  lifecycle redirect từng dispose route khi DocumentsUI active.

## Kế hoạch

- [x] Tạo nhánh sạch và xác minh device inventory.
- [x] Thêm guarded two-phase integration test và runner.
- [x] Chạy iOS export/restore system boundary.
- [x] Chạy Android export/restore system boundary trên AVD test tách biệt.
- [x] Cập nhật canonical evidence.
- [x] Chạy full gate.

## Nhật ký xác minh

| Command hoặc test | Kết quả | Ngày |
|---|---|---|
| iOS `device_integration.sh` | Pass toàn bộ phase và cleanup | 2026-07-29 |
| Android `device_integration.sh` lần đầu | Fail trước vault mutation: AVD chờ PIN sau reboot nên activity chưa resolve | 2026-07-29 |
| Android AVD tạm `device_integration.sh` | Pass secure storage, vault, lifecycle, navigation và cleanup | 2026-07-29 |
| Android encrypted backup `export` | Pass cancel, native save hợp lệ/tampered và clean-vault cleanup | 2026-07-29 |
| Android encrypted backup `restore` | Pass tamper, wrong password, preview cancel, exact atomic restore và cleanup | 2026-07-29 |
| iOS encrypted backup `export` | Pass cancel, save hợp lệ/tampered vào On My iPhone và cleanup | 2026-07-29 |
| iOS clean-install encrypted backup `restore` | Pass tamper, wrong password, preview cancel, exact atomic restore và cleanup | 2026-07-29 |
| Guard negative checks | Physical iPhone/macOS/invalid phase đều bị từ chối trước mutation | 2026-07-29 |
| `scripts/agent/check.sh full` | Pass docs/generated/format/analyze/platform, 258 Flutter test, backend/release/infra contract | 2026-07-29 |
| `scripts/agent/check_secrets.sh` | Pass 174 commit, không phát hiện leak | 2026-07-29 |

## Tác động tài liệu

- [x] `PROJECT_STATUS.md`
- [x] `SYSTEM_DESIGN.md`
- [x] `SECURITY.md`
- [x] `DEVELOPMENT.md`
- [x] `TESTING_STRATEGY.md`
- [x] `DEPLOYMENT.md`
- [x] ADR-0018

## Bàn giao

Đã có runtime evidence tái hiện được trên Android AVD/iOS Simulator mà không
chạm thiết bị thật hoặc production data. File test đã cleanup; iOS Files dùng
recoverable delete. AVD tạm đã xóa và AVD Pixel có PIN của owner không bị sửa.

Data contract không đổi: `.hyauth` v1 và local-vault COW giữ nguyên. Behavior đổi
ở Android save boundary và lifecycle phối hợp với system UI. Physical device,
packaged desktop, active screenshot prevention và store signing vẫn là gate riêng.
