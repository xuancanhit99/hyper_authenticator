begin;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.is_current_auth_session_active()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, auth
as $$
  select exists (
    select 1
    from auth.sessions as session
    where session.id::text = auth.jwt() ->> 'session_id'
      and session.user_id = auth.uid()
      and (session.not_after is null or session.not_after > now())
  );
$$;

revoke all on function private.is_current_auth_session_active()
  from public, anon;
grant execute on function private.is_current_auth_session_active()
  to authenticated;

drop policy if exists encrypted_vault_select_own
  on public.encrypted_vault_snapshots;
create policy encrypted_vault_select_own
  on public.encrypted_vault_snapshots
  for select
  to authenticated
  using (
    (select auth.uid()) = user_id
    and (select private.is_current_auth_session_active())
  );

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
set search_path = pg_catalog, public, auth, private
as $$
declare
  affected_rows integer;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
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
    raise sqlstate 'PT409' using message = 'revision_conflict';
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

comment on function private.is_current_auth_session_active() is
  'Returns true only when the signed JWT session still exists for auth.uid() and has not passed not_after.';
comment on function public.publish_encrypted_vault_snapshot is
  'Atomically publishes an encrypted snapshot for an active auth session when expected revision matches.';

commit;
