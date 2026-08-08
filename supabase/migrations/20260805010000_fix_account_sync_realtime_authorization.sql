begin;

-- Realtime 2.102.3 authorizes a private channel by inserting a temporary
-- message probe with topic + extension only. The probe's private column is
-- NULL, so channel privacy must come from the private join path itself rather
-- than a `messages.private is true` predicate. The database trigger still
-- calls realtime.send(..., true), therefore every application signal remains
-- private while the SELECT policy can evaluate the server's probe row.
drop policy account_sync_receive_own_broadcast on realtime.messages;

create policy account_sync_receive_own_broadcast
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and (select realtime.topic()) =
    'account-sync:' || (select auth.uid())::text
);

commit;
