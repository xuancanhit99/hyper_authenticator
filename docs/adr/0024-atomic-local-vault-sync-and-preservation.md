# ADR-0024: Atomic local vault sync và bảo toàn credential

- Trạng thái: Chấp nhận
- Ngày: 2026-10-21
- Owner: Owner phê duyệt hướng fix toàn bộ P1 trong chat ngày 21-10-2026
- Thay thế: Local persistence/ownership implementation của ADR-0020
- Bị thay thế bởi: Không

## Bối cảnh

Ghi downloaded account trước ownership có thể để lại mã không owner khi sync
thất bại. Chu kỳ dùng snapshot cũ cũng có thể ghi đè edit hoặc phục sinh delete
trong lúc chờ mạng. Hai context extension có thể tạo đè khóa và mất mutation.
Native Supabase dùng SharedPreferences; Android plugin mặc định reset khi lỗi.

## Quyết định

Local vault manifest `formatVersion: 3` chứa đồng thời account descriptors,
`syncMetadata` và `deletedAccountIds`. Giữ key prefix `ha:v2:` để đọc/migrate
copy-on-write artifacts cũ; format trong manifest/commit quyết định parser.
Một commit marker publish toàn bộ state. Hai generation hợp lệ được giữ lại;
rollback luôn payload và owner cùng nhau. Không khôi phục riêng payload remote.

`LocalVaultRepository` cung cấp snapshot và generation compare-and-set. Mọi
mutation UI và commit sync dùng cùng storage lock; network ở ngoài lock. Sync
bind unowned account trước network, stage download/ack trong bộ nhớ, rồi commit
với generation ban đầu. Conflict đọc lại/reconcile tối đa ba lần; còn cạnh tranh
thì báo retry, giữ mutation local. Delete ghi intent cùng generation, không suy
ra từ account vắng mặt sau mỗi request. Remote tombstone vẫn thắng offline edit.
Đổi user/sign-out hủy chu kỳ; từng RPC giữ Authorization của session đã kiểm tra.

Extension chọn key trong readwrite transaction chứa cả keys/records; chỉ init
khi vault chưa có record. Thiếu/hỏng key với ciphertext sẵn có là lỗi, không reset.
Web Locks bao trọn transaction Dart qua các context; context đóng thì browser
nhả lock. readAll lấy một IDB snapshot trước giải mã.

Native session và PKCE dùng secure envelopes theo Supabase origin. Migration
ghi + đọc verify trước xóa legacy preferences; secure envelope authoritative.
Logout persist null tombstone để bản legacy sót lại không phục sinh session.
Hosted Web giữ browser boundary; extension giữ namespace riêng hiện có.

Android giữ namespace/cipher, dùng resetOnError=false và migrateWithBackup=true.
Vendor flutter_secure_storage 10.3.1 có BSD license: abort khi backup decrypt
thiếu, verify target trước cleanup, kiểm commit progress. Không tuyên bố giữ
ciphertext có thể tái tạo Keystore key đã mất.

## Phương án đã cân nhắc

- Chỉ re-read trước save vẫn có race giữa read/write.
- Hold lock xuyên network làm UI chờ và không tạo crash-atomic ownership.
- Pending-download journal riêng cần nhiều phase/recovery hơn một manifest.
- Chỉ đổi Android option vẫn để migration bỏ qua corrupt backup entry.

## Migration và rollback

Lần đọc đầu nhập v1/v2 accounts và metadata v1 vào v3 trước mutation/network.
Metadata cũ lỗi thì fail closed. Missing local với metadata live trong format cũ
được chuyển một lần thành intent để giữ hợp đồng delete cũ. Không dùng lại
metadata key cũ sau khi đã có v3 hợp lệ. Legacy artifacts được giữ để operator
khôi phục, không cho old writer dùng tiếp.

Không downgrade về writer v2 sau migration: writer cũ không hiểu v3 và có thể
chọn generation cũ. Rollback ứng dụng cần bản vẫn hiểu v3 hoặc snapshot toàn bộ
storage trước migration và reconciliation có owner. Không restore riêng account
vào vault rỗng. Dữ liệu đã mất provenance do bản cũ không thể tự suy ra owner.

## Kiểm chứng

Fault injection record/manifest/commit, kể cả durable commit trước exception;
restart và đổi user; edit/delete/add trong list/upsert; stale CAS giữa datasource
instances; migration legacy metadata; native auth partial migration/tombstone;
Android Robolectric corruption preservation; Chrome contexts với cold-init
barrier, decrypt sau reopen, RMW, missing key. Old vault.js negative control lỗi
OperationError; patched code pass. Xem task P1 để biết build/runtime đã chạy.

## Giới hạn

Không E2EE, không portable backup/device registry/rotation, không release waiver.
Native storage lock trong một application process; hai process native ghi cùng
vault đồng thời chưa được hỗ trợ. Physical Android Keystore invalidation/upgrade
và Apple migration vẫn cần acceptance trên thiết bị thật.
