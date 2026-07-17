begin;

create table public.synced_accounts (
  user_id uuid not null references auth.users(id) on delete cascade,
  account_id uuid not null,
  issuer text not null check (char_length(issuer) between 1 and 255),
  account_name text not null check (char_length(account_name) between 1 and 512),
  secret_key text not null check (char_length(secret_key) between 16 and 512),
  algorithm text not null default 'SHA1'
    check (algorithm in ('SHA1', 'SHA256', 'SHA512')),
  digits smallint not null default 6 check (digits between 6 and 8),
  period integer not null default 30 check (period between 1 and 300),
  format_version smallint not null default 1 check (format_version = 1),
  updated_at timestamp with time zone not null default timezone('utc', now()),
  primary key (user_id, account_id)
);

comment on table public.synced_accounts is
  'Snapshot TOTP plaintext legacy; chưa phải E2EE và không production-ready.';
comment on column public.synced_accounts.secret_key is
  'Credential TOTP plaintext; không log, không đưa vào fixture hoặc telemetry.';

create index synced_accounts_user_updated_at_idx
  on public.synced_accounts (user_id, updated_at desc);

alter table public.synced_accounts enable row level security;
alter table public.synced_accounts force row level security;

revoke all on table public.synced_accounts from public, anon, authenticated;
grant select, insert, update, delete on table public.synced_accounts to authenticated;

create policy synced_accounts_select_own
  on public.synced_accounts
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy synced_accounts_insert_own
  on public.synced_accounts
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy synced_accounts_update_own
  on public.synced_accounts
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy synced_accounts_delete_own
  on public.synced_accounts
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

commit;
