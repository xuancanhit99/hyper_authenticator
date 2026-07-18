# Backup và khôi phục Supabase legacy

Tài liệu này ghi đúng artifact đã tạo trước khi clean instance legacy ngày
**17 tháng 7 năm 2026**. Backup không nằm trong Git repository.

## Vị trí và mức nhạy cảm

Vị trí hiện tại trên máy operator:

    /Users/canhvx/Backups/hyper_authenticator/supabase-legacy-20260717-193838

- Directory dùng mode `0700`; toàn bộ file dùng mode `0600`.
- Database dump chứa user, password hash, token lịch sử và provider credential.
- `stack-config-sensitive.tar.gz` chứa `.env` legacy cùng server secret.
- Không upload artifact vào issue, CI artifact, Git, cloud drive không mã hóa hoặc
  Supabase instance mới.
- Khi sao chép sang nơi khác, mã hóa archive và checksum bản mã hóa riêng.

## Inventory đã backup

| Artifact | Mục đích |
|---|---|
| `database-full.dump` | Full PostgreSQL custom-format dump để disaster recovery |
| `database-globals.sql` | Role/global object legacy; rất nhạy cảm |
| `database-schema-raw.sql` | Raw schema dump để audit/diff |
| `database-data-raw.sql` | Raw data dump |
| `public-schema.sql`, `public-data.sql` | Tách riêng schema/data `public` |
| `portable-critical-schema.sql` | DDL staging cho Auth, Storage và ba table `public` quan trọng |
| `portable-critical-data.sql` | Data staging tương ứng |
| `storage-files.tar.gz` | Storage filesystem; instance legacy không có object |
| `stack-config-sensitive.tar.gz` | Compose và `.env` legacy |
| `inventory-redacted.txt` | Version/count/config-key inventory đã redact |
| `legacy-mounts.txt` | Mount mapping để dựng lại layout cũ |
| `*.catalog.txt` | Catalog của dump/archive |
| `restore-rehearsal.txt` | Row count từ portable restore rehearsal |
| `SHA256SUMS` | Checksum của toàn bộ artifact chính |

Legacy database có logical size `13,374,255` byte và các row quan trọng:

| Table | Row |
|---|---:|
| `auth.users` | 2 |
| `storage.buckets` | 0 |
| `storage.objects` | 0 |
| `public.api_keys` | 4 |
| `public.provider_key_logs` | 3.342 |
| `public.user_provider_keys` | 2 |

Ba table `public` này thuộc workload legacy, không phải schema
`synced_accounts` của Hyper Authenticator.

## Xác minh trước khi dùng

Chạy từ backup directory sau mỗi lần sao chép:

    shasum -a 256 -c SHA256SUMS
    pg_restore --list database-full.dump >/dev/null
    tar -tzf storage-files.tar.gz >/dev/null
    tar -tzf stack-config-sensitive.tar.gz >/dev/null

Trên Linux có thể dùng `sha256sum -c SHA256SUMS`. Không tiếp tục restore nếu một
checksum sai, catalog không đọc được hoặc permission rộng hơn `0700/0600`.

Kết quả ngày tạo backup:

- toàn bộ checksum pass;
- custom dump catalog đọc được;
- hai tar archive đọc được;
- portable schema/data restore vào temporary database pass đúng row count ở bảng
  trên, sau đó temporary database đã bị xóa;
- full raw restore vào một database không khớp stack gặp restriction dự kiến ở
  Supabase internal role/function privilege. Full dump vì vậy chỉ được xem là
  disaster-recovery source cho một stack tương thích, chưa phải one-command
  portable restore.

## Cách 1: khôi phục nguyên trạng legacy

Dùng khi cần forensic hoặc chạy lại workload cũ, không dùng để nhập thẳng vào
instance Hyper Authenticator hiện tại.

1. Dựng một host/network cô lập và khớp inventory trong
   `inventory-redacted.txt`, đặc biệt PostgreSQL `15.8.1.085` cùng Auth/Storage
   legacy.
2. Xác minh checksum, giải nén config vào directory cô lập và review mọi public
   port/domain trước khi start. Không công bố instance ra Internet.
3. Review `database-globals.sql` trước khi áp dụng; file có role/password hash và
   có thể xung đột với role có sẵn.
4. Restore globals vào cluster trống, sau đó restore `database-full.dump` với
   `--exit-on-error`. Giữ log ở nơi riêng và redact credential/user data.
5. Khôi phục Storage filesystem theo `legacy-mounts.txt`. Backup hiện không có
   object nhưng vẫn phải khớp owner/permission của container.
6. So sánh row count với `restore-rehearsal.txt`, kiểm tra Auth và RLS trong
   environment cô lập.
7. Rotate JWT, database, SMTP, provider và service credential trước khi đưa vào
   sử dụng; việc rotate sẽ chủ động vô hiệu session legacy.

Không dùng `--clean` trên cluster chứa workload khác. Nên tạo cluster/database mới
thay vì restore đè.

## Cách 2: chuyển dữ liệu chọn lọc sang Supabase khác

Dùng khi chỉ cần cứu một phần data business cũ.

1. Tạo target Supabase mới và backup target trước khi import.
2. Restore `portable-critical-schema.sql` cùng
   `portable-critical-data.sql` vào temporary staging database trước. Hai file có
   DDL của `auth.users` và Storage nên **không** chạy trực tiếp lên một Supabase
   đang hoạt động.
3. Diff schema Auth/Storage giữa PostgreSQL 15 legacy và target. Với Auth, ưu tiên
   API/import workflow được version target hỗ trợ; direct insert vào `auth.users`
   chỉ thực hiện khi đã test migration tương thích và identity/session semantics.
4. Tạo migration riêng cho `public.api_keys`, `public.provider_key_logs` và
   `public.user_provider_keys`, sau đó transform/import data từ staging theo thứ
   tự foreign key.
5. Xem mọi provider/API key legacy là đã lộ trong backup: rotate hoặc vô hiệu hóa
   trước khi bật workload.
6. Reapply grant/RLS của target, chạy negative cross-user test và đối chiếu đúng
   row count. Không import policy/config legacy một cách mù quáng.
7. Storage legacy không có bucket/object; nếu backup tương lai có object thì phải
   restore cả database metadata lẫn file archive và đối chiếu hash từng object.

Hướng dẫn upstream về restore self-hosted cần được đối chiếu với version target:
[Supabase self-hosted restore guide](https://supabase.com/docs/guides/self-hosting/restore-from-platform).

## Instance mới hiện tại

Instance mới là fresh PostgreSQL 17, không nhận data legacy. Sau smoke/RLS test và
cleanup, `auth.users`, Auth audit, Storage bucket/object, Realtime message và
`public.synced_accounts` đều bằng `0`. Migration/system metadata được giữ để các
service hoạt động.
