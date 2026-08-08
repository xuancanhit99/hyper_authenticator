begin;

-- ADR-0020 thay thế hoàn toàn Minimal E2EE snapshot. Không giữ dual-write hoặc
-- compatibility fallback vì server không thể migrate HA1 ciphertext nếu thiếu
-- recovery key do người dùng giữ.
drop function if exists public.publish_encrypted_vault_snapshot(
  bigint, smallint, text, text, text, text, smallint, text, text, text
) cascade;
drop table if exists public.encrypted_vault_snapshots cascade;

create extension if not exists supabase_vault with schema vault;
create schema if not exists private;
revoke all on schema private from public;

create table public.authenticator_accounts (
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null,
  revision bigint not null check (revision > 0),
  vault_secret_id uuid unique references vault.secrets (id),
  updated_at timestamptz not null default timezone('utc', now()),
  deleted_at timestamptz,
  primary key (user_id, account_id),
  constraint authenticator_account_payload_state check (
    (deleted_at is null and vault_secret_id is not null)
    or (deleted_at is not null and vault_secret_id is null)
  )
);

alter table public.authenticator_accounts enable row level security;
alter table public.authenticator_accounts force row level security;
revoke all on public.authenticator_accounts from public, anon, authenticated;

create function private.is_valid_authenticator_payload(p_payload jsonb)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select jsonb_typeof(p_payload) = 'object'
    and p_payload ?& array[
      'issuer', 'accountName', 'secretKey', 'algorithm', 'digits', 'period'
    ]
    and not exists (
      select 1
      from jsonb_object_keys(p_payload) as key
      where key <> all (array[
        'issuer', 'accountName', 'secretKey', 'algorithm', 'digits', 'period'
      ])
    )
    and jsonb_typeof(p_payload -> 'issuer') = 'string'
    and char_length(p_payload ->> 'issuer') between 0 and 256
    and jsonb_typeof(p_payload -> 'accountName') = 'string'
    and char_length(p_payload ->> 'accountName') between 1 and 512
    and jsonb_typeof(p_payload -> 'secretKey') = 'string'
    and char_length(p_payload ->> 'secretKey') between 16 and 1024
    and (p_payload ->> 'secretKey') ~ '^[A-Z2-7]+=*$'
    and (p_payload ->> 'algorithm') in ('SHA1', 'SHA256', 'SHA512')
    and jsonb_typeof(p_payload -> 'digits') = 'number'
    and (p_payload ->> 'digits')::numeric =
      trunc((p_payload ->> 'digits')::numeric)
    and (p_payload ->> 'digits')::numeric between 6 and 8
    and jsonb_typeof(p_payload -> 'period') = 'number'
    and (p_payload ->> 'period')::numeric =
      trunc((p_payload ->> 'period')::numeric)
    and (p_payload ->> 'period')::numeric between 1 and 300;
$$;

revoke all on function private.is_valid_authenticator_payload(jsonb)
  from public, anon, authenticated;

create function private.delete_authenticator_vault_secret()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, vault
as $$
begin
  if old.vault_secret_id is not null then
    delete from vault.secrets where id = old.vault_secret_id;
  end if;
  return old;
end;
$$;

revoke all on function private.delete_authenticator_vault_secret()
  from public, anon, authenticated;

create trigger delete_authenticator_vault_secret
after delete on public.authenticator_accounts
for each row execute function private.delete_authenticator_vault_secret();

create function public.list_authenticator_accounts()
returns table (
  account_id uuid,
  revision bigint,
  updated_at timestamptz,
  deleted_at timestamptz,
  payload jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, vault
as $$
declare
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  return query
  select account.account_id,
         account.revision,
         account.updated_at,
         account.deleted_at,
         case
           when account.deleted_at is null
             then secret.decrypted_secret::jsonb
           else null::jsonb
         end as payload
  from public.authenticator_accounts as account
  left join vault.decrypted_secrets as secret
    on secret.id = account.vault_secret_id
  where account.user_id = current_user_id
  order by account.updated_at, account.account_id;
end;
$$;

create function public.upsert_authenticator_account(
  p_account_id uuid,
  p_expected_revision bigint,
  p_payload jsonb
)
returns table (
  account_id uuid,
  revision bigint,
  updated_at timestamptz,
  deleted_at timestamptz,
  payload jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, vault
as $$
declare
  current_user_id uuid;
  current_record public.authenticator_accounts%rowtype;
  new_secret_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_account_id is null
      or p_expected_revision is null
      or p_expected_revision < 0
      or not private.is_valid_authenticator_payload(p_payload) then
    raise exception 'invalid_account_payload' using errcode = '22023';
  end if;

  select * into current_record
  from public.authenticator_accounts as account
  where account.user_id = current_user_id
    and account.account_id = p_account_id
  for update;

  if not found then
    if p_expected_revision <> 0 then
      raise sqlstate 'PT409' using message = 'revision_conflict';
    end if;
    new_secret_id := vault.create_secret(p_payload::text);
    insert into public.authenticator_accounts (
      user_id, account_id, revision, vault_secret_id, updated_at, deleted_at
    ) values (
      current_user_id, p_account_id, 1, new_secret_id,
      timezone('utc', now()), null
    );
  else
    if current_record.deleted_at is not null then
      raise sqlstate 'PT410' using message = 'account_deleted';
    end if;
    if current_record.revision <> p_expected_revision then
      raise sqlstate 'PT409' using message = 'revision_conflict';
    end if;
    perform vault.update_secret(current_record.vault_secret_id, p_payload::text);
    update public.authenticator_accounts as account
    set revision = current_record.revision + 1,
        updated_at = timezone('utc', now())
    where account.user_id = current_user_id
      and account.account_id = p_account_id;
  end if;

  return query
  select account.account_id,
         account.revision,
         account.updated_at,
         account.deleted_at,
         p_payload
  from public.authenticator_accounts as account
  where account.user_id = current_user_id
    and account.account_id = p_account_id;
end;
$$;

create function public.delete_authenticator_account(
  p_account_id uuid,
  p_expected_revision bigint
)
returns table (
  account_id uuid,
  revision bigint,
  updated_at timestamptz,
  deleted_at timestamptz,
  payload jsonb
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, vault
as $$
declare
  current_user_id uuid;
  current_record public.authenticator_accounts%rowtype;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_account_id is null
      or p_expected_revision is null
      or p_expected_revision < 0 then
    raise exception 'invalid_delete_request' using errcode = '22023';
  end if;

  select * into current_record
  from public.authenticator_accounts as account
  where account.user_id = current_user_id
    and account.account_id = p_account_id
  for update;

  if not found then
    if p_expected_revision <> 0 then
      raise sqlstate 'PT409' using message = 'revision_conflict';
    end if;
    insert into public.authenticator_accounts (
      user_id, account_id, revision, vault_secret_id, updated_at, deleted_at
    ) values (
      current_user_id, p_account_id, 1, null,
      timezone('utc', now()), timezone('utc', now())
    );
  elsif current_record.deleted_at is null then
    if current_record.revision <> p_expected_revision then
      raise sqlstate 'PT409' using message = 'revision_conflict';
    end if;
    update public.authenticator_accounts as account
    set revision = current_record.revision + 1,
        vault_secret_id = null,
        updated_at = timezone('utc', now()),
        deleted_at = timezone('utc', now())
    where account.user_id = current_user_id
      and account.account_id = p_account_id;
    delete from vault.secrets where id = current_record.vault_secret_id;
  end if;

  return query
  select account.account_id,
         account.revision,
         account.updated_at,
         account.deleted_at,
         null::jsonb
  from public.authenticator_accounts as account
  where account.user_id = current_user_id
    and account.account_id = p_account_id;
end;
$$;

revoke all on function public.list_authenticator_accounts()
  from public, anon;
revoke all on function public.upsert_authenticator_account(uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.delete_authenticator_account(uuid, bigint)
  from public, anon;
grant execute on function public.list_authenticator_accounts()
  to authenticated;
grant execute on function public.upsert_authenticator_account(uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.delete_authenticator_account(uuid, bigint)
  to authenticated;

comment on table public.authenticator_accounts is
  'Per-account sync metadata; TOTP payload is stored only as Supabase Vault ciphertext.';
comment on function public.list_authenticator_accounts is
  'Returns decrypted records only for auth.uid() through an authenticated RPC.';
comment on function public.upsert_authenticator_account is
  'Creates or CAS-updates one active account; tombstones cannot be revived.';
comment on function public.delete_authenticator_account is
  'Creates an idempotent deletion tombstone for one account owned by auth.uid().';

commit;
