# Rollout Supabase E2EE snapshot

Tài liệu này ghi lại rollout additive ngày **18 tháng 7 năm 2026**. Không đặt
public URL, key, token, user ID hoặc nội dung backup trong repository.

## Kết quả

**Đã triển khai** trên Supabase self-hosted:

- table `public.encrypted_vault_snapshots`, một encrypted snapshot cho mỗi user;
- owner-only RLS và `FORCE ROW LEVEL SECURITY`;
- RPC `public.publish_encrypted_vault_snapshot` chạy atomic theo
  `expected_revision`;
- migration active-session guard buộc RLS/RPC đối chiếu JWT `session_id` với
  `auth.sessions` và optional `not_after`;
- client có bulk revoke mọi session khác, giữ session/local vault/DEK hiện tại;
- revision conflict dùng SQLSTATE `PT409`, được PostgREST trả về HTTP 409;
- table compatibility `public.synced_accounts` không bị drop hoặc sửa.

Native client đã bật encrypted sync cùng onboarding/recovery/conflict/key-rotation
flow. Plaintext compatibility bridge và Web cloud sync vẫn bị khóa; rollback không
được bật lại plaintext write.

## Backup trước thay đổi

Full PostgreSQL custom-format dump được tạo trước migration và lưu ngoài compose
tree, ngoài repository:

    /home/xuancanhit/backups/hyper-authenticator/pre-e2ee-20260717T192511Z.dump

- Kích thước tại thời điểm tạo: 314.051 byte.
- Quyền file: `0600`.
- Checksum sidecar đã được xác minh pass.
- Backup có thể chứa credential/system data; không tải vào issue, CI artifact
  hoặc repository.

## Bằng chứng xác minh

Migration được rehearsal bằng PostgreSQL ephemeral trước khi áp dụng. Sau deploy,
`scripts/supabase/test_remote_encrypted_vault_contract.sh` chạy qua public HTTPS
endpoint với hai isolated user, hai session cho User A và **20 kiểm tra pass**:

- anonymous không đọc được encrypted table;
- User A publish revision 1 và chỉ nhận encrypted envelope shape;
- User B không đọc row của User A;
- stale revision trả `revision_conflict`;
- đúng expected revision publish được revision 2;
- session cũ đọc được trước revoke, rồi bị RLS/RPC chặn ngay sau
  `scope=others` dù JWT chưa hết hạn;
- session hiện tại vẫn đọc/publish được sau revoke;
- User B không thể dùng RPC để update row User A.

Cleanup sau suite xác nhận `encrypted_vault_snapshots` còn 0 test row và không còn
isolated test user. Script dùng service-role operator key chỉ để tạo/dọn test user,
không in session/response và không dùng key đó trong Flutter client.

## Rollback

Rollback active-session guard ưu tiên giữ schema/data và revert riêng policy/RPC
về định nghĩa trong migration `20260718190000`; hệ quả là JWT của session vừa
revoke có thể truy cập vault tới `exp`. Chỉ drop helper sau khi policy/RPC không
còn dependency. Không cần và không được xóa encrypted row khi rollback control này.

Nếu bắt buộc gỡ toàn bộ encrypted schema:

1. xác nhận không có client đang ghi và backup mới nhất đã verify;
2. revoke execute RPC khỏi `authenticated`;
3. drop function `publish_encrypted_vault_snapshot`;
4. chỉ drop `encrypted_vault_snapshots` sau khi xác nhận không có snapshot cần giữ;
5. restore dump vào isolated instance trước, không restore đè production khi chưa
   rehearsal và đối chiếu version.

Không rollback bằng cách bật lại plaintext sync cho release build.

## Việc còn lại

- Recovery Web, TLS, Auth template, redirect allow-list và local
  `PASSWORD_RECOVERY_URL` đã deploy; còn SMTP mailbox/expired-token E2E.
- Device registry/revoke riêng từng thiết bị và device-specific key wrap.
- External alert channel, dedicated off-host backup và scheduled restore drill.
