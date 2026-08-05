# Roadmap

## Đã có trong source

- [x] TOTP local offline; add/edit/delete/search/copy/countdown.
- [x] Versioned copy-on-write local vault; logout giữ data.
- [x] Standard `otpauth` và Google migration QR import/export protected.
- [x] App Lock, Privacy Shield, responsive shell và ba visual style.
- [x] Account-managed automatic sync per-account với Vault/CAS/tombstone.
- [x] Private Realtime Broadcast wake-up trong source, giữ full-sync fallback.
- [x] Không còn recovery key/manual E2EE conflict flow.
- [x] GitHub Preview release harness.

## P0 — Rollout account sync

- [x] Full gate/build sau thay đổi.
- [x] Production preflight row count + full/off-host backup + restore rehearsal.
- [x] Deploy `20260804000000_create_account_managed_sync.sql`.
- [x] Remote two-user Vault/RPC/CAS/tombstone contract pass và cleanup verified.
- [ ] Android/iOS/Linux isolated runtime: iOS pass; Android/Linux còn thiếu.
- [ ] Phát hành client mới; ghi rõ server-managed encryption, không gọi E2EE.
- [ ] Independent security review cho RPC/Vault/root-key custody.

## P0 — Data/product

- [ ] Ownership/account-switch UX hoặc chính sách product rõ ràng.
- [ ] Tombstone retention/compaction không cho stale resurrection.
- [ ] Physical interoperability với Google Authenticator Android/iOS hiện tại.
- [ ] Benchmark/soak 100 và 500 account.

## P1 — Sync/UX

- [x] Production + iOS Simulator evidence cho private Realtime wake-up.
- [ ] Background retry theo capability platform, không làm lộ secret trong log.
- [ ] Group/favorite/reorder và batch delete/export.
- [ ] Scanner permission/torch/zoom/duplicate feedback trên thiết bị thật.
- [ ] TalkBack/VoiceOver/reduced-motion/full keyboard audit.

## P1 — Release/operations

- [ ] Android/iOS physical camera/biometric/upgrade/account-sync evidence.
- [ ] Apple/Windows/macOS store/signing/notarization gate.
- [ ] Public privacy/support/security URL và SMTP delivery.
- [ ] External alerting, off-host restore SLA và incident drill.

## P2 — Chỉ sau threat model/ADR mới

- [ ] Remote wipe local vault.
- [ ] Client-side zero-knowledge E2EE mới.
- [ ] Device/session registry hoặc ownership transfer protocol phức tạp.

Không thêm lại HA1 recovery, portable backup, per-device wrap, key rotation hoặc
compatibility fallback nếu chưa có ADR mới được owner duyệt.
