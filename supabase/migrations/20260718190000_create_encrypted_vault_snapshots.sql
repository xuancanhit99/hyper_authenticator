begin;

create table if not exists public.encrypted_vault_snapshots (
  user_id uuid primary key references auth.users (id) on delete cascade,
  format_version smallint not null check (format_version = 1),
  revision bigint not null check (revision > 0),
  cipher text not null check (cipher = 'AES-256-GCM'),
  nonce text not null check (char_length(nonce) between 16 and 32),
  ciphertext text not null check (char_length(ciphertext) between 1 and 10485760),
  auth_tag text not null check (char_length(auth_tag) between 20 and 32),
  key_format_version smallint not null check (key_format_version = 1),
  wrapped_key_nonce text not null check (char_length(wrapped_key_nonce) between 16 and 32),
  wrapped_key_ciphertext text not null check (char_length(wrapped_key_ciphertext) between 40 and 128),
  wrapped_key_auth_tag text not null check (char_length(wrapped_key_auth_tag) between 20 and 32),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.encrypted_vault_snapshots enable row level security;
alter table public.encrypted_vault_snapshots force row level security;

revoke all on public.encrypted_vault_snapshots from public, anon, authenticated;
grant select on public.encrypted_vault_snapshots to authenticated;

drop policy if exists encrypted_vault_select_own
  on public.encrypted_vault_snapshots;
create policy encrypted_vault_select_own
  on public.encrypted_vault_snapshots
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.publish_encrypted_vault_snapshot(
  p_expected_revision bigint,
  p_format_version smallint,
  p_cipher text,
  p_nonce text,
  p_ciphertext text,
  p_auth_tag text,
  p_key_format_version smallint,
  p_wrapped_key_nonce text,
  p_wrapped_key_ciphertext text,
  p_wrapped_key_auth_tag text
)
returns table (revision bigint, updated_at timestamptz)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  affected_rows integer;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_expected_revision < 0 then
    raise exception 'invalid_expected_revision' using errcode = '22023';
  end if;

  if p_expected_revision = 0 then
    insert into public.encrypted_vault_snapshots (
      user_id, format_version, revision, cipher, nonce, ciphertext, auth_tag,
      key_format_version, wrapped_key_nonce, wrapped_key_ciphertext,
      wrapped_key_auth_tag, updated_at
    ) values (
      current_user_id, p_format_version, 1, p_cipher, p_nonce, p_ciphertext,
      p_auth_tag, p_key_format_version, p_wrapped_key_nonce,
      p_wrapped_key_ciphertext, p_wrapped_key_auth_tag, timezone('utc', now())
    ) on conflict (user_id) do nothing;
  else
    update public.encrypted_vault_snapshots as snapshot
    set format_version = p_format_version,
        revision = p_expected_revision + 1,
        cipher = p_cipher,
        nonce = p_nonce,
        ciphertext = p_ciphertext,
        auth_tag = p_auth_tag,
        key_format_version = p_key_format_version,
        wrapped_key_nonce = p_wrapped_key_nonce,
        wrapped_key_ciphertext = p_wrapped_key_ciphertext,
        wrapped_key_auth_tag = p_wrapped_key_auth_tag,
        updated_at = timezone('utc', now())
    where snapshot.user_id = current_user_id
      and snapshot.revision = p_expected_revision;
  end if;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'revision_conflict' using errcode = '40001';
  end if;

  return query
  select snapshot.revision, snapshot.updated_at
  from public.encrypted_vault_snapshots as snapshot
  where snapshot.user_id = current_user_id;
end;
$$;

revoke all on function public.publish_encrypted_vault_snapshot(
  bigint, smallint, text, text, text, text, smallint, text, text, text
) from public, anon;
grant execute on function public.publish_encrypted_vault_snapshot(
  bigint, smallint, text, text, text, text, smallint, text, text, text
) to authenticated;

comment on table public.encrypted_vault_snapshots is
  'E2EE versioned snapshot; ciphertext only, one current snapshot per authenticated user.';
comment on function public.publish_encrypted_vault_snapshot is
  'Atomically publishes an encrypted snapshot when expected revision matches.';

commit;
