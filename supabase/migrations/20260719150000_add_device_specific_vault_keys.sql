begin;

create or replace function private.is_canonical_base64url(
  p_value text,
  p_expected_octets integer
)
returns boolean
language plpgsql
immutable
strict
set search_path = pg_catalog
as $$
declare
  decoded bytea;
  expected_length integer;
begin
  if p_expected_octets < 1 then
    return false;
  end if;
  expected_length := ((p_expected_octets + 2) / 3) * 4;
  if char_length(p_value) <> expected_length
     or p_value !~ '^[A-Za-z0-9_-]+={0,2}$' then
    return false;
  end if;
  decoded := decode(translate(p_value, '-_', '+/'), 'base64');
  return octet_length(decoded) = p_expected_octets
    and translate(encode(decoded, 'base64'), '+/', '-_') = p_value;
exception
  when others then
    return false;
end;
$$;

revoke all on function private.is_canonical_base64url(text, integer)
  from public, anon, authenticated;

alter table public.encrypted_vault_snapshots
  add column if not exists key_generation bigint not null default 1,
  add column if not exists device_wrap_version smallint not null default 0;

alter table public.encrypted_vault_snapshots
  drop constraint if exists encrypted_vault_key_generation_positive,
  add constraint encrypted_vault_key_generation_positive
    check (key_generation > 0),
  drop constraint if exists encrypted_vault_device_wrap_version_allowed,
  add constraint encrypted_vault_device_wrap_version_allowed
    check (device_wrap_version in (0, 1));

create table if not exists private.encrypted_vault_membership_verifiers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  key_generation bigint not null check (key_generation > 0),
  verifier text not null check (private.is_canonical_base64url(verifier, 32)),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table private.encrypted_vault_membership_verifiers enable row level security;
alter table private.encrypted_vault_membership_verifiers force row level security;
revoke all on private.encrypted_vault_membership_verifiers
  from public, anon, authenticated;

create table if not exists public.authenticator_device_keys (
  device_key_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  installation_id uuid not null,
  public_key text not null,
  binding_secret_hash bytea not null,
  state text not null default 'pending',
  created_at timestamptz not null default now(),
  wrapped_at timestamptz,
  activated_at timestamptz,
  revoked_at timestamptz,
  constraint authenticator_device_keys_owner_id_unique
    unique (user_id, device_key_id),
  constraint authenticator_device_keys_owner_installation_unique
    unique (user_id, device_key_id, installation_id),
  constraint authenticator_device_keys_public_key_canonical
    check (private.is_canonical_base64url(public_key, 32)),
  constraint authenticator_device_keys_binding_hash_length
    check (octet_length(binding_secret_hash) = 32),
  constraint authenticator_device_keys_state_allowed
    check (state in ('pending', 'wrapped', 'active', 'revoked')),
  constraint authenticator_device_keys_state_timestamps
    check (
      (state = 'pending' and wrapped_at is null and activated_at is null and revoked_at is null)
      or (state = 'wrapped' and wrapped_at is not null and activated_at is null and revoked_at is null)
      or (state = 'active' and wrapped_at is not null and activated_at is not null and revoked_at is null)
      or (state = 'revoked' and revoked_at is not null)
    )
);

create unique index if not exists authenticator_device_keys_installation_live_idx
  on public.authenticator_device_keys (user_id, installation_id)
  where revoked_at is null;

create unique index if not exists authenticator_device_keys_public_key_live_idx
  on public.authenticator_device_keys (user_id, public_key)
  where revoked_at is null;

create index if not exists authenticator_device_keys_user_state_idx
  on public.authenticator_device_keys (user_id, state, created_at);

alter table public.authenticator_device_keys enable row level security;
alter table public.authenticator_device_keys force row level security;
revoke all on table public.authenticator_device_keys
  from public, anon, authenticated;

create table if not exists public.authenticator_device_key_wraps (
  device_key_id uuid primary key,
  user_id uuid not null,
  key_generation bigint not null,
  format_version smallint not null,
  kem text not null,
  kdf text not null,
  aead text not null,
  encapsulated_key text not null,
  ciphertext text not null,
  auth_tag text not null,
  membership_proof text not null,
  created_at timestamptz not null default now(),
  constraint authenticator_device_key_wraps_owner_fk
    foreign key (user_id, device_key_id)
    references public.authenticator_device_keys (user_id, device_key_id)
    on delete cascade,
  constraint authenticator_device_key_wraps_generation_positive
    check (key_generation > 0),
  constraint authenticator_device_key_wraps_suite
    check (
      format_version = 1
      and kem = 'DHKEM-X25519-HKDF-SHA256'
      and kdf = 'HKDF-SHA256'
      and aead = 'AES-256-GCM'
    ),
  constraint authenticator_device_key_wraps_encapsulated_key_canonical
    check (private.is_canonical_base64url(encapsulated_key, 32)),
  constraint authenticator_device_key_wraps_ciphertext_canonical
    check (private.is_canonical_base64url(ciphertext, 32)),
  constraint authenticator_device_key_wraps_auth_tag_canonical
    check (private.is_canonical_base64url(auth_tag, 16)),
  constraint authenticator_device_key_wraps_membership_proof_canonical
    check (private.is_canonical_base64url(membership_proof, 32))
);

create index if not exists authenticator_device_key_wraps_user_generation_idx
  on public.authenticator_device_key_wraps (user_id, key_generation);

alter table public.authenticator_device_key_wraps enable row level security;
alter table public.authenticator_device_key_wraps force row level security;
revoke all on table public.authenticator_device_key_wraps
  from public, anon, authenticated;

alter table public.authenticator_device_sessions
  add column if not exists device_key_id uuid;

alter table public.authenticator_device_sessions
  drop constraint if exists authenticator_device_sessions_device_key_fk,
  add constraint authenticator_device_sessions_device_key_fk
    foreign key (user_id, device_key_id, installation_id)
    references public.authenticator_device_keys (
      user_id, device_key_id, installation_id
    );

create index if not exists authenticator_device_sessions_device_key_idx
  on public.authenticator_device_sessions (user_id, device_key_id)
  where device_key_id is not null and revoked_at is null;

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
  current_protocol smallint;
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

  if p_expected_revision > 0 then
    select snapshot.device_wrap_version
    into current_protocol
    from public.encrypted_vault_snapshots as snapshot
    where snapshot.user_id = current_user_id;
    if current_protocol = 1 then
      raise exception 'device_key_protocol_required' using errcode = '0A000';
    end if;
  end if;

  if p_expected_revision = 0 then
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
      and snapshot.revision = p_expected_revision
      and snapshot.device_wrap_version = 0;
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
  if p_expected_revision < 0 or p_expected_key_generation < 0 then
    raise exception 'invalid_expected_version' using errcode = '22023';
  end if;

  if p_expected_revision > 0 then
    select snapshot.device_wrap_version
    into current_protocol
    from public.encrypted_vault_snapshots as snapshot
    where snapshot.user_id = current_user_id;
    if current_protocol = 1 then
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
    end if;
  end if;

  if p_expected_revision = 0 then
    if p_expected_key_generation <> 0 then
      raise exception 'invalid_initial_key_generation' using errcode = '22023';
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
      and snapshot.revision = p_expected_revision
      and snapshot.key_generation = p_expected_key_generation;
  end if;

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

create or replace function public.begin_authenticator_device_key_enrollment(
  p_installation_id uuid,
  p_public_key text,
  p_binding_secret text
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
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  if not private.is_canonical_base64url(p_public_key, 32)
     or not private.is_canonical_base64url(p_binding_secret, 32) then
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
    raise sqlstate 'PT409' using message = 'device_key_conflict';
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

create or replace function public.list_authenticator_device_keys()
returns table (
  device_key_id uuid,
  installation_id uuid,
  public_key text,
  device_state text,
  created_at timestamptz,
  wrapped_at timestamptz,
  activated_at timestamptz,
  is_current boolean,
  key_generation bigint,
  format_version smallint,
  kem text,
  kdf text,
  aead text,
  encapsulated_key text,
  ciphertext text,
  auth_tag text,
  membership_proof text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid;
  current_session_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  current_session_id := (auth.jwt() ->> 'session_id')::uuid;

  return query
  select
    device_key.device_key_id,
    device_key.installation_id,
    device_key.public_key,
    device_key.state,
    device_key.created_at,
    device_key.wrapped_at,
    device_key.activated_at,
    coalesce(session_device.session_id = current_session_id, false),
    key_wrap.key_generation,
    key_wrap.format_version,
    key_wrap.kem,
    key_wrap.kdf,
    key_wrap.aead,
    key_wrap.encapsulated_key,
    key_wrap.ciphertext,
    key_wrap.auth_tag,
    key_wrap.membership_proof
  from public.authenticator_device_keys as device_key
  left join public.authenticator_device_key_wraps as key_wrap
    on key_wrap.device_key_id = device_key.device_key_id
   and key_wrap.user_id = device_key.user_id
  left join public.authenticator_device_sessions as session_device
    on session_device.device_key_id = device_key.device_key_id
   and session_device.user_id = device_key.user_id
   and session_device.session_id = current_session_id
   and session_device.revoked_at is null
  where device_key.user_id = current_user_id
    and device_key.revoked_at is null
  order by
    session_device.session_id = current_session_id desc,
    device_key.created_at,
    device_key.device_key_id;
end;
$$;

create or replace function public.publish_authenticator_device_key_wrap(
  p_target_device_key_id uuid,
  p_current_binding_secret text,
  p_expected_key_generation bigint,
  p_format_version smallint,
  p_kem text,
  p_kdf text,
  p_aead text,
  p_encapsulated_key text,
  p_ciphertext text,
  p_auth_tag text,
  p_vault_membership_verifier text,
  p_membership_proof text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid;
  current_session_id uuid;
  source_device_key_id uuid;
  source_state text;
  target_state text;
  current_generation bigint;
  current_protocol smallint;
  stored_membership_verifier text;
  affected_rows integer;
  binding_hash bytea;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  if not private.is_canonical_base64url(p_current_binding_secret, 32)
     or p_format_version <> 1
     or p_kem <> 'DHKEM-X25519-HKDF-SHA256'
     or p_kdf <> 'HKDF-SHA256'
     or p_aead <> 'AES-256-GCM'
     or not private.is_canonical_base64url(p_encapsulated_key, 32)
     or not private.is_canonical_base64url(p_ciphertext, 32)
     or not private.is_canonical_base64url(p_auth_tag, 16)
     or not private.is_canonical_base64url(p_vault_membership_verifier, 32)
     or not private.is_canonical_base64url(p_membership_proof, 32) then
    raise exception 'invalid_device_wrap' using errcode = '22023';
  end if;
  binding_hash := sha256(
    decode(translate(p_current_binding_secret, '-_', '+/'), 'base64')
  );
  current_session_id := (auth.jwt() ->> 'session_id')::uuid;

  select session_device.device_key_id, source_key.state
  into source_device_key_id, source_state
  from public.authenticator_device_sessions as session_device
  join public.authenticator_device_keys as source_key
    on source_key.device_key_id = session_device.device_key_id
   and source_key.user_id = session_device.user_id
  where session_device.user_id = current_user_id
    and session_device.session_id = current_session_id
    and session_device.revoked_at is null
    and source_key.revoked_at is null
    and source_key.binding_secret_hash = binding_hash
  for update of source_key, session_device;
  if source_device_key_id is null then
    raise exception 'device_binding_required' using errcode = '42501';
  end if;

  select snapshot.key_generation, snapshot.device_wrap_version
  into current_generation, current_protocol
  from public.encrypted_vault_snapshots as snapshot
  where snapshot.user_id = current_user_id
  for update;
  if current_generation is null then
    raise sqlstate 'PT404' using message = 'encrypted_vault_not_found';
  end if;
  if current_generation <> p_expected_key_generation then
    raise sqlstate 'PT409' using message = 'key_generation_conflict';
  end if;
  select membership.verifier
  into stored_membership_verifier
  from private.encrypted_vault_membership_verifiers as membership
  where membership.user_id = current_user_id
    and membership.key_generation = current_generation
  for update;
  if stored_membership_verifier is null then
    if current_protocol <> 0 or source_device_key_id <> p_target_device_key_id then
      raise exception 'vault_membership_verifier_required'
        using errcode = '42501';
    end if;
    insert into private.encrypted_vault_membership_verifiers (
      user_id, key_generation, verifier
    ) values (
      current_user_id, current_generation, p_vault_membership_verifier
    ) on conflict (user_id) do nothing;
    select membership.verifier
    into stored_membership_verifier
    from private.encrypted_vault_membership_verifiers as membership
    where membership.user_id = current_user_id
      and membership.key_generation = current_generation;
  end if;
  if stored_membership_verifier <> p_vault_membership_verifier then
    raise exception 'vault_membership_verifier_invalid' using errcode = '42501';
  end if;

  select target_key.state
  into target_state
  from public.authenticator_device_keys as target_key
  where target_key.device_key_id = p_target_device_key_id
    and target_key.user_id = current_user_id
    and target_key.revoked_at is null
  for update;
  if target_state is null then
    raise sqlstate 'PT404' using message = 'device_key_not_found';
  end if;
  if target_state not in ('pending', 'wrapped') then
    raise sqlstate 'PT409' using message = 'device_key_already_active';
  end if;
  if source_state <> 'active' and source_device_key_id <> p_target_device_key_id then
    raise exception 'trusted_source_device_required' using errcode = '42501';
  end if;
  if source_state = 'active' and not exists (
    select 1
    from public.authenticator_device_key_wraps as source_wrap
    where source_wrap.user_id = current_user_id
      and source_wrap.device_key_id = source_device_key_id
      and source_wrap.key_generation = current_generation
  ) then
    raise exception 'current_source_wrap_required' using errcode = '42501';
  end if;

  insert into public.authenticator_device_key_wraps (
    device_key_id, user_id, key_generation, format_version, kem, kdf, aead,
    encapsulated_key, ciphertext, auth_tag, membership_proof
  ) values (
    p_target_device_key_id, current_user_id, current_generation,
    p_format_version, p_kem, p_kdf, p_aead, p_encapsulated_key, p_ciphertext,
    p_auth_tag, p_membership_proof
  ) on conflict (device_key_id) do nothing;
  get diagnostics affected_rows = row_count;

  if affected_rows = 0 and not exists (
    select 1
    from public.authenticator_device_key_wraps as existing_wrap
    where existing_wrap.device_key_id = p_target_device_key_id
      and existing_wrap.user_id = current_user_id
      and existing_wrap.key_generation = current_generation
      and existing_wrap.format_version = p_format_version
      and existing_wrap.kem = p_kem
      and existing_wrap.kdf = p_kdf
      and existing_wrap.aead = p_aead
      and existing_wrap.encapsulated_key = p_encapsulated_key
      and existing_wrap.ciphertext = p_ciphertext
      and existing_wrap.auth_tag = p_auth_tag
      and existing_wrap.membership_proof = p_membership_proof
  ) then
    raise sqlstate 'PT409' using message = 'device_wrap_conflict';
  end if;

  update public.authenticator_device_keys as target_key
  set state = 'wrapped',
      wrapped_at = coalesce(target_key.wrapped_at, now())
  where target_key.device_key_id = p_target_device_key_id
    and target_key.user_id = current_user_id
    and target_key.state = 'pending';

  return true;
end;
$$;

create or replace function public.confirm_current_authenticator_device_key(
  p_device_key_id uuid,
  p_binding_secret text,
  p_expected_key_generation bigint
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid;
  current_session_id uuid;
  binding_hash bytea;
  current_generation bigint;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  if not private.is_canonical_base64url(p_binding_secret, 32) then
    raise exception 'invalid_device_binding' using errcode = '22023';
  end if;
  binding_hash := sha256(
    decode(translate(p_binding_secret, '-_', '+/'), 'base64')
  );
  current_session_id := (auth.jwt() ->> 'session_id')::uuid;

  select snapshot.key_generation
  into current_generation
  from public.encrypted_vault_snapshots as snapshot
  where snapshot.user_id = current_user_id
  for update;
  if current_generation <> p_expected_key_generation then
    raise sqlstate 'PT409' using message = 'key_generation_conflict';
  end if;

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
      and session_device.device_key_id = p_device_key_id
      and session_device.revoked_at is null
      and device_key.state in ('wrapped', 'active')
      and device_key.revoked_at is null
      and device_key.binding_secret_hash = binding_hash
      and key_wrap.key_generation = current_generation
  ) then
    raise exception 'verified_current_device_wrap_required'
      using errcode = '42501';
  end if;

  update public.authenticator_device_keys as device_key
  set state = 'active',
      activated_at = coalesce(device_key.activated_at, now())
  where device_key.device_key_id = p_device_key_id
    and device_key.user_id = current_user_id
    and device_key.state in ('wrapped', 'active')
    and device_key.revoked_at is null;

  update public.encrypted_vault_snapshots as snapshot
  set device_wrap_version = 1
  where snapshot.user_id = current_user_id
    and snapshot.key_generation = current_generation
    and exists (
      select 1
      from private.encrypted_vault_membership_verifiers as membership
      where membership.user_id = current_user_id
        and membership.key_generation = current_generation
    );

  return true;
end;
$$;

create or replace function public.rotate_encrypted_vault_device_keys(
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
  p_wrapped_key_auth_tag text,
  p_next_vault_membership_verifier text,
  p_device_wraps jsonb,
  p_excluded_device_key_ids uuid[]
)
returns table (
  revision bigint,
  key_generation bigint,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid;
  current_session_id uuid;
  source_device_key_id uuid;
  binding_hash bytea;
  new_generation bigint;
  active_count integer;
  wrap_count integer;
  excluded_count integer;
  affected_rows integer;
  item jsonb;
  item_key text;
  item_key_count integer;
  target_device_key_id uuid;
  wrap_device_ids uuid[] := array[]::uuid[];
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  if p_expected_revision < 1 or p_expected_key_generation < 1
     or not private.is_canonical_base64url(p_current_binding_secret, 32)
     or not private.is_canonical_base64url(p_next_vault_membership_verifier, 32)
     or jsonb_typeof(p_device_wraps) <> 'array'
     or p_excluded_device_key_ids is null then
    raise exception 'invalid_device_rotation_request' using errcode = '22023';
  end if;
  wrap_count := jsonb_array_length(p_device_wraps);
  excluded_count := cardinality(p_excluded_device_key_ids);
  if wrap_count not between 1 and 32 or excluded_count > 31
     or array_position(p_excluded_device_key_ids, null) is not null
     or (
       select count(*) <> count(distinct excluded_id)
       from unnest(p_excluded_device_key_ids) as excluded_id
     ) then
    raise exception 'invalid_device_rotation_set' using errcode = '22023';
  end if;
  binding_hash := sha256(
    decode(translate(p_current_binding_secret, '-_', '+/'), 'base64')
  );
  current_session_id := (auth.jwt() ->> 'session_id')::uuid;

  select session_device.device_key_id
  into source_device_key_id
  from public.authenticator_device_sessions as session_device
  join public.authenticator_device_keys as source_key
    on source_key.device_key_id = session_device.device_key_id
   and source_key.user_id = session_device.user_id
  join public.authenticator_device_key_wraps as source_wrap
    on source_wrap.device_key_id = source_key.device_key_id
   and source_wrap.user_id = source_key.user_id
  where session_device.user_id = current_user_id
    and session_device.session_id = current_session_id
    and session_device.revoked_at is null
    and source_key.state = 'active'
    and source_key.revoked_at is null
    and source_key.binding_secret_hash = binding_hash
    and source_wrap.key_generation = p_expected_key_generation
  for update of source_key, session_device, source_wrap;
  if source_device_key_id is null then
    raise exception 'active_device_binding_required' using errcode = '42501';
  end if;
  if source_device_key_id = any(p_excluded_device_key_ids) then
    raise exception 'cannot_exclude_current_device_key' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.encrypted_vault_snapshots as snapshot
    where snapshot.user_id = current_user_id
      and snapshot.revision = p_expected_revision
      and snapshot.key_generation = p_expected_key_generation
      and snapshot.device_wrap_version = 1
    for update
  ) then
    raise sqlstate 'PT409' using message = 'revision_or_generation_conflict';
  end if;
  new_generation := p_expected_key_generation + 1;

  for item in select value from jsonb_array_elements(p_device_wraps)
  loop
    if jsonb_typeof(item) <> 'object' then
      raise exception 'invalid_device_wrap_set' using errcode = '22023';
    end if;
    select count(*) into item_key_count from jsonb_object_keys(item);
    if item_key_count <> 10 or item <> jsonb_strip_nulls(item) then
      raise exception 'invalid_device_wrap_set' using errcode = '22023';
    end if;
    for item_key in select jsonb_object_keys(item)
    loop
      if item_key not in (
        'device_key_id', 'key_generation', 'format_version', 'kem', 'kdf',
        'aead', 'encapsulated_key', 'ciphertext', 'auth_tag', 'membership_proof'
      ) then
        raise exception 'invalid_device_wrap_set' using errcode = '22023';
      end if;
    end loop;
    if jsonb_typeof(item -> 'device_key_id') <> 'string'
       or jsonb_typeof(item -> 'key_generation') <> 'number'
       or jsonb_typeof(item -> 'format_version') <> 'number'
       or jsonb_typeof(item -> 'kem') <> 'string'
       or jsonb_typeof(item -> 'kdf') <> 'string'
       or jsonb_typeof(item -> 'aead') <> 'string'
       or jsonb_typeof(item -> 'encapsulated_key') <> 'string'
       or jsonb_typeof(item -> 'ciphertext') <> 'string'
       or jsonb_typeof(item -> 'auth_tag') <> 'string'
       or jsonb_typeof(item -> 'membership_proof') <> 'string' then
      raise exception 'invalid_device_wrap_set' using errcode = '22023';
    end if;
    begin
      target_device_key_id := (item ->> 'device_key_id')::uuid;
    exception
      when others then
        raise exception 'invalid_device_wrap_set' using errcode = '22023';
    end;
    if target_device_key_id = any(wrap_device_ids)
       or target_device_key_id = any(p_excluded_device_key_ids)
       or item ->> 'key_generation' <> new_generation::text
       or item ->> 'format_version' <> '1'
       or item ->> 'kem' <> 'DHKEM-X25519-HKDF-SHA256'
       or item ->> 'kdf' <> 'HKDF-SHA256'
       or item ->> 'aead' <> 'AES-256-GCM'
       or not private.is_canonical_base64url(item ->> 'encapsulated_key', 32)
       or not private.is_canonical_base64url(item ->> 'ciphertext', 32)
       or not private.is_canonical_base64url(item ->> 'auth_tag', 16)
       or not private.is_canonical_base64url(item ->> 'membership_proof', 32)
       or not exists (
         select 1
         from public.authenticator_device_keys as target_key
         where target_key.device_key_id = target_device_key_id
           and target_key.user_id = current_user_id
           and target_key.state = 'active'
           and target_key.revoked_at is null
       ) then
      raise exception 'invalid_device_wrap_set' using errcode = '22023';
    end if;
    wrap_device_ids := array_append(wrap_device_ids, target_device_key_id);
  end loop;

  select count(*)
  into active_count
  from public.authenticator_device_keys as active_key
  where active_key.user_id = current_user_id
    and active_key.state = 'active'
    and active_key.revoked_at is null;
  if active_count <> wrap_count + excluded_count
     or exists (
       select 1
       from unnest(p_excluded_device_key_ids) as excluded_id
       where not exists (
         select 1
         from public.authenticator_device_keys as excluded_key
         where excluded_key.device_key_id = excluded_id
           and excluded_key.user_id = current_user_id
           and excluded_key.state = 'active'
           and excluded_key.revoked_at is null
       )
     )
     or exists (
       select 1
       from public.authenticator_device_keys as active_key
       where active_key.user_id = current_user_id
         and active_key.state = 'active'
         and active_key.revoked_at is null
         and not (active_key.device_key_id = any(wrap_device_ids))
         and not (active_key.device_key_id = any(p_excluded_device_key_ids))
     ) then
    raise sqlstate 'PT409' using message = 'incomplete_device_wrap_set';
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
      key_generation = new_generation,
      device_wrap_version = 1,
      updated_at = timezone('utc', now())
  where snapshot.user_id = current_user_id
    and snapshot.revision = p_expected_revision
    and snapshot.key_generation = p_expected_key_generation
    and snapshot.device_wrap_version = 1;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise sqlstate 'PT409' using message = 'revision_or_generation_conflict';
  end if;

  update private.encrypted_vault_membership_verifiers as membership
  set key_generation = new_generation,
      verifier = p_next_vault_membership_verifier,
      updated_at = timezone('utc', now())
  where membership.user_id = current_user_id
    and membership.key_generation = p_expected_key_generation;
  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'vault_membership_verifier_missing' using errcode = '42501';
  end if;

  update public.authenticator_device_keys as pending_key
  set state = 'pending', wrapped_at = null
  where pending_key.user_id = current_user_id
    and pending_key.state = 'wrapped'
    and pending_key.revoked_at is null;

  delete from public.authenticator_device_key_wraps as old_wrap
  where old_wrap.user_id = current_user_id;

  insert into public.authenticator_device_key_wraps (
    device_key_id, user_id, key_generation, format_version, kem, kdf, aead,
    encapsulated_key, ciphertext, auth_tag, membership_proof
  )
  select
    (entry ->> 'device_key_id')::uuid,
    current_user_id,
    (entry ->> 'key_generation')::bigint,
    (entry ->> 'format_version')::smallint,
    entry ->> 'kem',
    entry ->> 'kdf',
    entry ->> 'aead',
    entry ->> 'encapsulated_key',
    entry ->> 'ciphertext',
    entry ->> 'auth_tag',
    entry ->> 'membership_proof'
  from jsonb_array_elements(p_device_wraps) as wrapped(entry);

  update public.authenticator_device_keys as excluded_key
  set state = 'revoked', revoked_at = now()
  where excluded_key.user_id = current_user_id
    and excluded_key.device_key_id = any(p_excluded_device_key_ids)
    and excluded_key.state = 'active'
    and excluded_key.revoked_at is null;

  update public.authenticator_device_sessions as excluded_session
  set revoked_at = now()
  where excluded_session.user_id = current_user_id
    and excluded_session.device_key_id = any(p_excluded_device_key_ids)
    and excluded_session.revoked_at is null;

  delete from auth.sessions as auth_session
  where auth_session.user_id = current_user_id
    and exists (
      select 1
      from public.authenticator_device_sessions as excluded_session
      where excluded_session.user_id = current_user_id
        and excluded_session.session_id = auth_session.id
        and excluded_session.device_key_id = any(p_excluded_device_key_ids)
        and excluded_session.revoked_at is not null
    );

  return query
  select snapshot.revision, snapshot.key_generation, snapshot.updated_at
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

revoke all on function public.begin_authenticator_device_key_enrollment(
  uuid, text, text
) from public, anon;
grant execute on function public.begin_authenticator_device_key_enrollment(
  uuid, text, text
) to authenticated;

revoke all on function public.list_authenticator_device_keys()
  from public, anon;
grant execute on function public.list_authenticator_device_keys()
  to authenticated;

revoke all on function public.publish_authenticator_device_key_wrap(
  uuid, text, bigint, smallint, text, text, text, text, text, text, text, text
) from public, anon;
grant execute on function public.publish_authenticator_device_key_wrap(
  uuid, text, bigint, smallint, text, text, text, text, text, text, text, text
) to authenticated;

revoke all on function public.confirm_current_authenticator_device_key(
  uuid, text, bigint
) from public, anon;
grant execute on function public.confirm_current_authenticator_device_key(
  uuid, text, bigint
) to authenticated;

revoke all on function public.rotate_encrypted_vault_device_keys(
  bigint, bigint, text, smallint, text, text, text, text, smallint, text,
  text, text, text, jsonb, uuid[]
) from public, anon;
grant execute on function public.rotate_encrypted_vault_device_keys(
  bigint, bigint, text, smallint, text, text, text, text, smallint, text,
  text, text, text, jsonb, uuid[]
) to authenticated;

comment on column public.encrypted_vault_snapshots.key_generation is
  'Monotonic DEK generation, independent from snapshot revision.';
comment on column public.encrypted_vault_snapshots.device_wrap_version is
  'Zero keeps legacy publishing compatible; one requires generation-aware v2 publishing.';
comment on table private.encrypted_vault_membership_verifiers is
  'Server-only HMAC verifier derived from the current DEK; never exposed by client SELECT or device RPCs.';
comment on table public.authenticator_device_keys is
  'Per-installation X25519 public key and hashed binding secret; private key never leaves client secure storage.';
comment on table public.authenticator_device_key_wraps is
  'Exact current-generation HPKE DEK wrap and opaque client-verifiable membership proof per active device key.';
comment on function public.begin_authenticator_device_key_enrollment is
  'Creates or resumes one pending key bound to the JWT current native device session; never returns the binding hash.';
comment on function public.publish_authenticator_device_key_wrap is
  'Publishes an immutable current-generation HPKE wrap from a bound device; target must confirm after local unwrap.';
comment on function public.confirm_current_authenticator_device_key is
  'Marks only the JWT current bound device active after the client has verified its own wrap.';
comment on function public.rotate_encrypted_vault_device_keys is
  'Atomically rotates snapshot DEK generation, exact surviving wrap set and excluded device sessions.';

commit;
