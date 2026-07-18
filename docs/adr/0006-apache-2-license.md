# ADR-0006: Phát hành source theo Apache License 2.0

- Trạng thái: Chấp nhận
- Ngày: 2026-07-18
- Owner: canhvx
- Thay thế: P-008
- Bị thay thế bởi:

## Bối cảnh

Repository chưa có license nên người khác không có quyền rõ ràng để dùng, sửa hoặc
phân phối source dù project hướng tới cộng tác lâu dài.

## Quyết định

Dùng Apache License 2.0 cho source do project sở hữu. Dependency, font, logo, tên
thương hiệu và asset bên thứ ba vẫn theo license/quyền riêng của chúng; Apache-2.0
không tự cấp quyền trademark.

## Phương án đã cân nhắc

- MIT: ngắn hơn nhưng không có patent grant/termination rõ như Apache-2.0.
- GPL: bảo đảm copyleft nhưng không phù hợp mục tiêu permissive integration.
- Proprietary: hạn chế cộng tác và phân phối đa nền tảng.

## Hệ quả

Contributor/distributor phải giữ copyright, license và NOTICE nếu có. Trước public
release vẫn cần audit provenance của font/logo/asset; quyết định này không khẳng
định mọi asset hiện tại có quyền redistributable.

## Bảo mật và quyền riêng tư

License không thay thế security warranty, privacy policy hoặc incident process.

## Dữ liệu và compatibility

Không tác động runtime/data contract.

## Xác minh

Root có `LICENSE`, README link tới license và dependency/asset audit là release gate.

## Rollout

Thêm full license text; thêm `NOTICE` khi audit phát hiện attribution bắt buộc.
