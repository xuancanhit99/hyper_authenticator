begin;

-- ADR-0021: Realtime chỉ là private wake-up signal. Dữ liệu account tiếp tục
-- đi qua authenticated RPC ADR-0020; không publish row hoặc Vault reference.
do $$
begin
  if to_regclass('public.authenticator_accounts') is null then
    raise exception 'account_sync_schema_required';
  end if;
  if to_regclass('realtime.messages') is null
      or to_regprocedure('realtime.send(jsonb,text,text,boolean)') is null then
    raise exception 'supabase_realtime_broadcast_required';
  end if;
end;
$$;

create function private.broadcast_account_sync_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, realtime
as $$
begin
  perform realtime.send(
    jsonb_build_object('version', 1),
    'account-sync-changed',
    'account-sync:' || new.user_id::text,
    true
  );
  return new;
end;
$$;

revoke all on function private.broadcast_account_sync_change()
  from public, anon, authenticated;

create trigger broadcast_account_sync_change
after insert or update on public.authenticator_accounts
for each row execute function private.broadcast_account_sync_change();

-- Private channel authorization được đánh giá lúc join. Chỉ cấp quyền nhận
-- Broadcast đúng topic của auth.uid(); cố ý không tạo INSERT policy nên client
-- không thể tự phát wake-up signal.
create policy account_sync_receive_own_broadcast
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension = 'broadcast'
  and realtime.messages.private is true
  and (select realtime.topic()) =
    'account-sync:' || (select auth.uid())::text
);

comment on function private.broadcast_account_sync_change is
  'Emits a credential-free private wake-up signal after account sync mutations.';

commit;
