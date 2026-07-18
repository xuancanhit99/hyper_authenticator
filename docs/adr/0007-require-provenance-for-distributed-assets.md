# ADR-0007: Chỉ phân phối asset có provenance rõ ràng

- Trạng thái: Chấp nhận
- Ngày: 2026-07-18

## Bối cảnh

Repository từng bundle Averta, một font thương mại cần license riêng cho app/Web,
và 1.047 logo thương hiệu dịch vụ không có source/license/NOTICE. Apache-2.0 của
source không cấp quyền phân phối các file đó hoặc quyền trademark.

## Quyết định

Release chỉ bundle asset do project/owner kiểm soát hoặc asset bên thứ ba có exact
provenance, license, attribution và trademark-purpose review. Loại Averta, logo
pack, map và ảnh không dùng. Account UI render avatar ký tự bằng Material widget;
logo không trở thành persisted field.

Asset bên thứ ba mới phải đi kèm:

1. source URL/version/hash;
2. license/EULA cho đúng loại phân phối;
3. attribution/NOTICE nếu cần;
4. xác nhận trademark chỉ dùng để nhận diện đúng service;
5. inventory update và build/test evidence.

## Hệ quả

- Artifact giảm khoảng 28 MiB và không phân phối font/logo chưa rõ quyền.
- UI mất logo thương hiệu nhưng giữ khả năng nhận diện bằng issuer initial.
- Không cần data migration hoặc rollback vì logo trước đây được suy ra từ issuer.
- Muốn khôi phục icon pack phải qua audit theo checklist trên, không copy file cũ lại.

## Xác minh

- `rg` không còn reference Averta/logo map.
- `flutter analyze`, `flutter test` và platform build pass.
- `pubspec.yaml` chỉ bundle branding được dùng bởi app/splash/launcher.
