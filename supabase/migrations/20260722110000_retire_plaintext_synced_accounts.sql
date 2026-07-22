begin;

-- Never let FORCE RLS or a policy-filtered owner make count(*) look empty.
-- A non-BYPASSRLS operator now errors instead of seeing a filtered zero.
set local row_security = off;

-- Never silently destroy a legacy credential.  Production deployment must
-- have a verified backup and this precondition must remain zero.
do $$
declare
  legacy_row_count bigint;
begin
  if to_regclass('public.synced_accounts') is null then
    return;
  end if;

  -- Serialize the zero-row precondition with every legacy reader/writer and
  -- keep the lock until COMMIT. Without this lock, a concurrent INSERT could
  -- commit after count(*) returned zero but before DROP TABLE acquired its
  -- own lock, silently destroying the newly committed credential.
  execute 'lock table public.synced_accounts in access exclusive mode';
  execute 'select count(*) from public.synced_accounts'
    into legacy_row_count;
  if legacy_row_count <> 0 then
    raise exception 'plaintext_legacy_rows_present'
      using errcode = '55000',
            detail = format(
              'public.synced_accounts contains %s row(s); back up and migrate before retrying',
              legacy_row_count
            );
  end if;

  -- Keep DROP in the same existence branch as the lock/count. If the table was
  -- absent at the check, never issue a later unconditional DROP that could
  -- destroy a same-name table concurrently created by another transaction.
  execute 'drop table public.synced_accounts';
end;
$$;

commit;
