begin;

-- The legacy RPC remains only for creating revision 1.  Every later write must
-- first enroll and confirm a device key, then use the bound v2 RPC.
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
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'invalid_expected_revision' using errcode = '22023';
  end if;
  if p_expected_revision <> 0 then
    raise exception 'device_key_protocol_required' using errcode = '0A000';
  end if;

  insert into public.encrypted_vault_snapshots (
    user_id, format_version, revision, cipher, nonce, ciphertext, auth_tag,
    key_format_version, wrapped_key_nonce, wrapped_key_ciphertext,
    wrapped_key_auth_tag, key_generation, device_wrap_version, updated_at
  ) values (
    current_user_id, p_format_version, 1, p_cipher, p_nonce, p_ciphertext,
    p_auth_tag, p_key_format_version, p_wrapped_key_nonce,
    p_wrapped_key_ciphertext, p_wrapped_key_auth_tag, 1, 0,
    timezone('utc', now())
  ) on conflict (user_id) do nothing;

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

-- Lock the exact snapshot before reading its protocol.  This makes protocol
-- activation and publish mutually exclusive and closes the previous TOCTOU
-- window where a protocol-0 publish could commit after confirmation switched
-- the same row to protocol 1.
create or replace function public.publish_encrypted_vault_snapshot_v2(
  p_expected_revision bigint,
  p_expected_key_generation bigint,
  p_current_binding_secret text,
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
returns table (
  revision bigint,
  key_generation bigint,
  device_wrap_version smallint,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  affected_rows integer;
  current_user_id uuid;
  current_session_id uuid;
  current_protocol smallint;
  binding_hash bytea;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  if p_expected_revision < 1 or p_expected_key_generation < 1 then
    raise exception 'invalid_expected_version' using errcode = '22023';
  end if;

  select snapshot.device_wrap_version
  into current_protocol
  from public.encrypted_vault_snapshots as snapshot
  where snapshot.user_id = current_user_id
    and snapshot.revision = p_expected_revision
    and snapshot.key_generation = p_expected_key_generation
  for update;
  if not found then
    raise sqlstate 'PT409' using message = 'revision_or_generation_conflict';
  end if;
  if current_protocol <> 1 then
    raise exception 'device_key_protocol_required' using errcode = '0A000';
  end if;
  if not private.is_canonical_base64url(p_current_binding_secret, 32) then
    raise exception 'active_device_binding_required' using errcode = '42501';
  end if;

  binding_hash := sha256(
    decode(translate(p_current_binding_secret, '-_', '+/'), 'base64')
  );
  current_session_id := (auth.jwt() ->> 'session_id')::uuid;
  if not exists (
    select 1
    from public.authenticator_device_sessions as session_device
    join public.authenticator_device_keys as device_key
      on device_key.device_key_id = session_device.device_key_id
     and device_key.user_id = session_device.user_id
    join public.authenticator_device_key_wraps as key_wrap
      on key_wrap.device_key_id = device_key.device_key_id
     and key_wrap.user_id = device_key.user_id
    where session_device.user_id = current_user_id
      and session_device.session_id = current_session_id
      and session_device.revoked_at is null
      and device_key.state = 'active'
      and device_key.revoked_at is null
      and device_key.binding_secret_hash = binding_hash
      and key_wrap.key_generation = p_expected_key_generation
  ) then
    raise exception 'active_device_binding_required' using errcode = '42501';
  end if;

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
    and snapshot.revision = p_expected_revision
    and snapshot.key_generation = p_expected_key_generation
    and snapshot.device_wrap_version = 1;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise sqlstate 'PT409' using message = 'revision_or_generation_conflict';
  end if;

  return query
  select snapshot.revision, snapshot.key_generation,
         snapshot.device_wrap_version, snapshot.updated_at
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

revoke all on function public.publish_encrypted_vault_snapshot_v2(
  bigint, bigint, text, smallint, text, text, text, text, smallint, text, text,
  text
) from public, anon;
grant execute on function public.publish_encrypted_vault_snapshot_v2(
  bigint, bigint, text, smallint, text, text, text, text, smallint, text, text,
  text
) to authenticated;

comment on function public.publish_encrypted_vault_snapshot is
  'Creates revision 1 only; later writes require a confirmed device key and v2 RPC.';
comment on function public.publish_encrypted_vault_snapshot_v2 is
  'Publishes only after row-locked protocol-1 and active-device binding checks.';

commit;
