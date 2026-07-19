begin;

drop function if exists public.begin_authenticator_device_key_enrollment(
  uuid, text, text
);

create or replace function public.begin_authenticator_device_key_enrollment(
  p_installation_id uuid,
  p_public_key text,
  p_binding_secret text,
  p_vault_membership_verifier text
)
returns table (
  device_key_id uuid,
  device_state text,
  key_generation bigint
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid;
  current_session_id uuid;
  current_generation bigint;
  existing_key public.authenticator_device_keys%rowtype;
  binding_hash bytea;
  stored_membership_verifier text;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  if not private.is_canonical_base64url(p_public_key, 32)
     or not private.is_canonical_base64url(p_binding_secret, 32)
     or not private.is_canonical_base64url(p_vault_membership_verifier, 32) then
    raise exception 'invalid_device_key_material' using errcode = '22023';
  end if;
  binding_hash := sha256(
    decode(translate(p_binding_secret, '-_', '+/'), 'base64')
  );
  current_session_id := (auth.jwt() ->> 'session_id')::uuid;

  if not exists (
    select 1
    from public.authenticator_device_sessions as session_device
    where session_device.user_id = current_user_id
      and session_device.session_id = current_session_id
      and session_device.installation_id = p_installation_id
      and session_device.revoked_at is null
      and session_device.platform in ('android', 'ios', 'macos', 'windows', 'linux')
  ) then
    raise exception 'native_device_session_registration_required'
      using errcode = '22023';
  end if;

  select snapshot.key_generation
  into current_generation
  from public.encrypted_vault_snapshots as snapshot
  where snapshot.user_id = current_user_id
  for update;
  if current_generation is null then
    raise sqlstate 'PT404' using message = 'encrypted_vault_not_found';
  end if;
  select membership.verifier
  into stored_membership_verifier
  from private.encrypted_vault_membership_verifiers as membership
  where membership.user_id = current_user_id
    and membership.key_generation = current_generation;

  select device_key.*
  into existing_key
  from public.authenticator_device_keys as device_key
  where device_key.user_id = current_user_id
    and device_key.installation_id = p_installation_id
    and device_key.revoked_at is null
  for update;

  if existing_key.device_key_id is null then
    insert into public.authenticator_device_keys (
      user_id, installation_id, public_key, binding_secret_hash
    ) values (
      current_user_id, p_installation_id, p_public_key, binding_hash
    ) returning * into existing_key;
  elsif existing_key.public_key <> p_public_key
        or existing_key.binding_secret_hash <> binding_hash then
    if stored_membership_verifier is null
       or stored_membership_verifier <> p_vault_membership_verifier then
      raise exception 'device_key_recovery_proof_invalid' using errcode = '42501';
    end if;
    update public.authenticator_device_keys as old_key
    set state = 'revoked',
        revoked_at = now()
    where old_key.device_key_id = existing_key.device_key_id
      and old_key.user_id = current_user_id;
    delete from public.authenticator_device_key_wraps as old_wrap
    where old_wrap.device_key_id = existing_key.device_key_id
      and old_wrap.user_id = current_user_id;
    update public.authenticator_device_sessions as old_session
    set revoked_at = now()
    where old_session.user_id = current_user_id
      and old_session.device_key_id = existing_key.device_key_id
      and old_session.session_id <> current_session_id
      and old_session.revoked_at is null;
    delete from auth.sessions as auth_session
    using public.authenticator_device_sessions as old_session
    where old_session.user_id = current_user_id
      and old_session.device_key_id = existing_key.device_key_id
      and old_session.session_id <> current_session_id
      and old_session.revoked_at is not null
      and auth_session.id = old_session.session_id
      and auth_session.user_id = current_user_id;
    insert into public.authenticator_device_keys (
      user_id, installation_id, public_key, binding_secret_hash
    ) values (
      current_user_id, p_installation_id, p_public_key, binding_hash
    ) returning * into existing_key;
  end if;

  update public.authenticator_device_sessions as session_device
  set device_key_id = existing_key.device_key_id,
      last_seen_at = now()
  where session_device.user_id = current_user_id
    and session_device.session_id = current_session_id
    and session_device.installation_id = p_installation_id
    and session_device.revoked_at is null;

  return query select existing_key.device_key_id, existing_key.state,
                      current_generation;
end;
$$;

revoke all on function public.begin_authenticator_device_key_enrollment(
  uuid, text, text, text
) from public, anon;
grant execute on function public.begin_authenticator_device_key_enrollment(
  uuid, text, text, text
) to authenticated;

comment on function public.begin_authenticator_device_key_enrollment is
  'Creates/resumes a pending key; DEK-verifier recovery may replace a lost local key and revoke sessions still bound to the old key.';

commit;
