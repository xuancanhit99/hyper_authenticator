# ADR-0002: Local vault dùng versioned copy-on-write snapshot

- Trạng thái: Chấp nhận
- Ngày: 2026-07-18
- Owner: Repository owner
- Thay thế: Legacy record/index write nhiều bước không có recovery
- Bị thay thế bởi:

## Bối cảnh

Legacy local storage ghi mỗi account theo UUID và giữ một JSON index riêng. Add
ghi record trước index; delete xóa record trước index. Crash hoặc storage failure
giữa hai bước tạo orphan/dangling record, còn concurrent mutation có thể làm mất
update. `FlutterSecureStorage` không cung cấp transaction đa key dùng chung trên
sáu platform và Web.

## Quyết định

- Giữ `FlutterSecureStorage` làm secure-storage abstraction.
- Serialize operation trong mỗi app process.
- Dùng namespace `ha:v2` với immutable record, versioned manifest và commit
  marker. Commit marker được ghi và verify cuối cùng là publication point.
- Mỗi mutation tạo generation mới; record không đổi được tái sử dụng, record đổi
  có key immutable mới.
- Reader chọn committed generation mới nhất còn đọc/validate được và fallback về
  generation cũ nếu manifest hoặc record mới hỏng.
- Lần đọc đầu tự migrate legacy data: repair dangling ID, recover UUID-keyed
  orphan có payload hợp lệ, bỏ qua record hỏng và chỉ publish v2 sau verify.
- Không xóa legacy key trong rollout hiện tại để rollback còn khả thi.

## Phương án đã cân nhắc

### Tiếp tục record/index và thêm retry

Ít code hơn nhưng retry không tạo atomicity; crash vẫn có thể rơi giữa record và
index, concurrent read-modify-write vẫn lost update. Không chọn.

### Lưu toàn bộ vault trong một secure-storage value

Có một publication write nhưng mọi mutation phải ghi lại toàn bộ ciphertext và
khó giữ generation rollback rõ ràng. Không chọn cho baseline này.

### Chuyển sang transactional database

Có transaction tốt hơn nhưng cần database encryption key lifecycle, migration và
plugin verification riêng trên mọi target. Có thể xem lại khi vault lớn hơn.

## Hệ quả

### Tích cực

- Partial write trước commit không thay snapshot đang active.
- Corrupt generation mới có thể fallback về generation trước.
- Stable account ID được giữ qua restore/sync merge.
- Migration không xóa legacy data.

### Tiêu cực

- Secure storage tăng kích thước vì giữ lịch sử và legacy key.
- `readAll` cùng validation generation tốn thêm I/O.
- Serialization chỉ bảo vệ một data-source instance, không phải distributed lock.

### Rủi ro

- Nếu commit write thành công nhưng response/verification lỗi, caller có thể nhận
  failure trong khi restart nhìn thấy generation mới. Caller phải reload/reconcile.
- Chưa có compaction. Trước production cần retention policy giữ tối thiểu một
  generation rollback và xóa unreachable record theo best-effort sau commit.
- Native secure-storage behavior vẫn cần device integration test.

## Bảo mật và quyền riêng tư

Record vẫn nằm trong platform secure storage và chứa TOTP credential; key name,
manifest và test output không được chứa secret. Legacy record được giữ có chủ ý
để rollback nên secure deletion chưa được khẳng định.

## Dữ liệu và compatibility

Reader v2 dual-read legacy khi chưa có valid committed snapshot. Rollout không
ghi ngược legacy format. Rollback app về client legacy vẫn thấy legacy snapshot
trước migration nhưng không thấy mutation mới; vì vậy chỉ rollback client khi đã
chấp nhận giới hạn này hoặc có export/migration ngược được test.

## Xác minh

- Migration indexed record và orphan; legacy key được giữ.
- Concurrent add không lost update.
- Commit failure giữ snapshot trước.
- Corrupt latest manifest fallback generation trước.
- Corrupt legacy index/record không che record UUID hợp lệ.
- Delete không xóa legacy rollback copy.

## Rollout

1. Release reader/writer v2 cùng regression test.
2. Quan sát storage failure đã sanitize và xác minh trên platform chính.
3. Chỉ thiết kế compaction sau khi có retention/rollback test.
4. Rollback nếu migration không tìm được committed snapshot hoặc device test cho
   thấy platform secure storage không hỗ trợ `readAll` ổn định.
