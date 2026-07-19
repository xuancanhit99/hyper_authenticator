# Quyết định kiến trúc

Tài liệu này lập chỉ mục quyết định bền vững. Quyết định mới có ảnh hưởng dài hạn cần record riêng trong `docs/adr`.

## Quyết định đã áp dụng

| ID | Quyết định | Trạng thái | Bằng chứng |
|---|---|---|---|
| A-001 | Flutter/Dart cho client đa nền tảng | Đã áp dụng | `pubspec.yaml`, sáu platform runner và Web |
| A-002 | Presentation/Domain/Data theo feature | Đã áp dụng, chưa tuyệt đối | `lib/features` |
| A-003 | BLoC cho feature state, Provider cho theme | Đã áp dụng | `flutter_bloc`, `ThemeProvider` |
| A-004 | GetIt/Injectable cho dependency | Đã áp dụng | `injection_container*` |
| A-005 | FlutterSecureStorage cho TOTP record | Đã áp dụng | Authenticator local data source |
| A-006 | SharedPreferences cho preference không phải secret | Đã áp dụng | Theme, lock, sync, Remember Me |
| A-007 | Supabase cho authentication và remote sync | Đã áp dụng | Auth/sync data source |
| A-008 | fpdart `Either` tại repository/use-case boundary | Đã áp dụng | Domain/data layer |
| A-009 | GoRouter redirect từ auth và app-lock state | Đã áp dụng | `AppRouter` |
| A-010 | Supabase client config qua compile-time `dart-define` | Đã áp dụng | `AppConfig`, `.env.example` |
| A-011 | Shared Auth/Accounts BLoC instance cho UI và sync | Đã áp dụng | Lazy singleton + `BlocProvider.value` |
| A-012 | Logout giữ authenticator data local | Đã áp dụng | `AuthBloc` |
| A-013 | Swift Package Manager là Apple dependency manager duy nhất | Đã áp dụng | iOS/macOS project |
| A-014 | Capability theo platform được kiểm soát tập trung | Đã áp dụng | `PlatformCapabilities` |
| A-015 | Pin self-hosted Supabase release và version hóa remote snake_case/RLS contract | Đã áp dụng | [ADR-0001](adr/0001-pin-self-hosted-supabase-and-remote-contract.md) |
| A-016 | Local vault dùng versioned copy-on-write snapshot | Đã áp dụng | [ADR-0002](adr/0002-versioned-local-vault-storage.md) |
| A-017 | Local vault offline độc lập Supabase identity | Chấp nhận | [ADR-0003](adr/0003-offline-first-local-vault.md) |
| A-018 | Web là password-recovery surface canonical | Chấp nhận | [ADR-0004](adr/0004-web-password-recovery.md) |
| A-019 | E2EE versioned snapshot và user-held recovery key | Chấp nhận theo giai đoạn | [ADR-0005](adr/0005-e2ee-versioned-snapshot-sync.md) |
| A-020 | Source dùng Apache License 2.0 | Chấp nhận | [ADR-0006](adr/0006-apache-2-license.md) |
| A-021 | Chỉ phân phối asset có provenance/license rõ ràng | Chấp nhận | [ADR-0007](adr/0007-require-provenance-for-distributed-assets.md) |
| A-022 | Encrypted vault chỉ cho auth session còn active; client bulk revoke session khác | Chấp nhận | [ADR-0008](adr/0008-enforce-active-session-for-encrypted-vault.md) |
| A-023 | Đóng băng Windows storage identity tương thích release lịch sử | Chấp nhận | [ADR-0009](adr/0009-freeze-windows-storage-identity.md) |
| A-024 | GitHub Releases là binary channel đầu tiên; Windows/Linux unsigned chỉ phát hành dưới dạng preview | Chấp nhận | [ADR-0010](adr/0010-github-preview-release-first.md) |
| A-025 | Device registry bind server-side với auth session; targeted revoke không được mô tả là cryptographic device ban | Chấp nhận | [ADR-0011](adr/0011-bind-device-registry-to-auth-session.md) |

Đã áp dụng không đồng nghĩa production-ready; defect/risk nằm trong `PROJECT_STATUS.md`.

## Quyết định đang đề xuất

| ID | Quyết định | Trạng thái | Bằng chứng |
|---|---|---|---|
| A-026 | Device-specific DEK wrap dùng HPKE, DEK-derived membership proof và atomic key-generation rotation | Đề xuất; primitive staged, chưa inject/deploy | [ADR-0012](adr/0012-device-specific-hpke-key-wrap.md) |

## Quyết định còn mở

| ID đề xuất | Quyết định cần có | Lý do |
|---|---|---|
| P-006 | Platform support/SLA chính thức | Build matrix chưa phải product commitment |
| P-007 | Tên identifier dài hạn | Display name đã thống nhất, bundle ID cũ được giữ để bảo toàn install identity |
| P-009 | Web security/support level | Browser storage khác native secure storage |

## Khi nào cần ADR

Tạo ADR khi thay đổi trust boundary/cryptography, persisted contract, platform/backend được hỗ trợ, destructive data semantics, state ownership chính hoặc dependency strategy dài hạn.

Quy trình:

1. Sao chép `docs/adr/0000-template.md`.
2. Gán số và slug.
3. Ghi context, decision, alternative, consequence, migration, rollback, verification.
4. Đặt trạng thái **Đề xuất**, lấy phê duyệt owner rồi chuyển **Chấp nhận**.
5. Thêm record vào chỉ mục và đánh dấu **Bị thay thế** thay vì sửa lịch sử.
