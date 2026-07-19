begin;

create table if not exists public.authenticator_device_sessions (
  registration_id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  session_id uuid not null unique,
  installation_id uuid not null,
  display_name text not null,
  platform text not null,
  registered_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint authenticator_device_display_name_length check (
    char_length(display_name) between 1 and 80
  ),
  constraint authenticator_device_platform_allowed check (
    platform in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown')
  )
);

create index if not exists authenticator_device_sessions_user_active_idx
  on public.authenticator_device_sessions (user_id, last_seen_at desc)
  where revoked_at is null;

alter table public.authenticator_device_sessions enable row level security;
alter table public.authenticator_device_sessions force row level security;
revoke all on table public.authenticator_device_sessions
  from public, anon, authenticated;

create or replace function public.register_current_authenticator_device(
  p_installation_id uuid,
  p_display_name text,
  p_platform text
)
returns table (registration_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid;
  current_session_id uuid;
  normalized_name text;
  normalized_platform text;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;

  current_session_id := (auth.jwt() ->> 'session_id')::uuid;
  normalized_name := btrim(p_display_name);
  normalized_platform := lower(btrim(p_platform));
  if char_length(normalized_name) not between 1 and 80 then
    raise exception 'invalid_device_name' using errcode = '22023';
  end if;
  if normalized_platform not in (
    'android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown'
  ) then
    raise exception 'invalid_device_platform' using errcode = '22023';
  end if;

  delete from public.authenticator_device_sessions as device
  where device.user_id = current_user_id
    and device.last_seen_at < now() - interval '30 days'
    and not exists (
      select 1
      from auth.sessions as active_session
      where active_session.id = device.session_id
        and active_session.user_id = current_user_id
        and (
          active_session.not_after is null
          or active_session.not_after > now()
        )
    );

  return query
  insert into public.authenticator_device_sessions as device (
    user_id,
    session_id,
    installation_id,
    display_name,
    platform,
    registered_at,
    last_seen_at,
    revoked_at
  ) values (
    current_user_id,
    current_session_id,
    p_installation_id,
    normalized_name,
    normalized_platform,
    now(),
    now(),
    null
  )
  on conflict (session_id) do update
  set installation_id = excluded.installation_id,
      display_name = excluded.display_name,
      platform = excluded.platform,
      last_seen_at = now(),
      revoked_at = null
  where device.user_id = current_user_id
  returning device.registration_id;
end;
$$;

create or replace function public.list_authenticator_device_sessions()
returns table (
  registration_id uuid,
  display_name text,
  platform text,
  registered_at timestamptz,
  last_seen_at timestamptz,
  is_current boolean
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
    device.registration_id,
    device.display_name,
    device.platform,
    device.registered_at,
    device.last_seen_at,
    device.session_id = current_session_id
  from public.authenticator_device_sessions as device
  join auth.sessions as active_session
    on active_session.id = device.session_id
   and active_session.user_id = device.user_id
   and (
     active_session.not_after is null
     or active_session.not_after > now()
   )
  where device.user_id = current_user_id
    and device.revoked_at is null
  order by
    device.session_id = current_session_id desc,
    device.last_seen_at desc,
    device.registration_id;
end;
$$;

create or replace function public.revoke_authenticator_device_session(
  p_registration_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  current_user_id uuid;
  current_session_id uuid;
  target_session_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not private.is_current_auth_session_active() then
    raise exception 'session_revoked' using errcode = '42501';
  end if;
  current_session_id := (auth.jwt() ->> 'session_id')::uuid;

  select device.session_id
  into target_session_id
  from public.authenticator_device_sessions as device
  where device.registration_id = p_registration_id
    and device.user_id = current_user_id
    and device.revoked_at is null
  for update;

  if target_session_id is null then
    raise sqlstate 'PT404' using message = 'device_session_not_found';
  end if;
  if target_session_id = current_session_id then
    raise exception 'cannot_revoke_current_device_session'
      using errcode = '22023';
  end if;

  update public.authenticator_device_sessions as device
  set revoked_at = now()
  where device.registration_id = p_registration_id
    and device.user_id = current_user_id;

  delete from auth.sessions as target_session
  where target_session.id = target_session_id
    and target_session.user_id = current_user_id;

  return true;
end;
$$;

revoke all on function public.register_current_authenticator_device(
  uuid, text, text
) from public, anon;
grant execute on function public.register_current_authenticator_device(
  uuid, text, text
) to authenticated;

revoke all on function public.list_authenticator_device_sessions()
  from public, anon;
grant execute on function public.list_authenticator_device_sessions()
  to authenticated;

revoke all on function public.revoke_authenticator_device_session(uuid)
  from public, anon;
grant execute on function public.revoke_authenticator_device_session(uuid)
  to authenticated;

comment on table public.authenticator_device_sessions is
  'Pseudonymous client registration metadata bound server-side to one active auth session; contains no token or vault key.';
comment on function public.register_current_authenticator_device is
  'Registers only the JWT current session; client cannot choose user_id or session_id.';
comment on function public.list_authenticator_device_sessions is
  'Lists active registered sessions owned by auth.uid() without exposing auth session IDs.';
comment on function public.revoke_authenticator_device_session is
  'Revokes one owned non-current registered auth session; re-login is allowed.';

commit;
