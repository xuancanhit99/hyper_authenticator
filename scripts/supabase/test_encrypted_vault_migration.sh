#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MIGRATIONS=(
  "$ROOT/supabase/migrations/20260718190000_create_encrypted_vault_snapshots.sql"
  "$ROOT/supabase/migrations/20260718230000_enforce_active_vault_sessions.sql"
  "$ROOT/supabase/migrations/20260719070000_create_authenticator_device_registry.sql"
  "$ROOT/supabase/migrations/20260719150000_add_device_specific_vault_keys.sql"
  "$ROOT/supabase/migrations/20260719170000_allow_recovery_device_key_replacement.sql"
)
IMAGE=${POSTGRES_TEST_IMAGE:-postgres:17-alpine@sha256:979c4379dd698aba0b890599a6104e082035f98ef31d9b9291ec22f2b13059ca}
CONTAINER="hyper-auth-e2ee-postgres-test-$$"

cleanup() {
  docker container rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run --detach --name "$CONTAINER" \
  --env POSTGRES_PASSWORD=TEST_ONLY_PASSWORD \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=256m \
  "$IMAGE" >/dev/null

attempt=0
until docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [[ "$attempt" -ge 30 ]]; then
    docker logs "$CONTAINER" >&2
    exit 1
  fi
  sleep 1
done

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key);
create table auth.sessions (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  not_after timestamptz
);
create function auth.jwt() returns jsonb
language sql stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), ''),
    '{}'
  )::jsonb
$$;
create function auth.uid() returns uuid
language sql stable
as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;
grant usage on schema auth, public to anon, authenticated;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated;
insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');
insert into auth.sessions (id, user_id) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   '11111111-1111-4111-8111-111111111111'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   '22222222-2222-4222-8222-222222222222');
SQL

for migration in "${MIGRATIONS[@]}"; do
  docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
    <"$migration"
done

publish_sql() {
  local expected_revision=$1
  local session_id=${2:-aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa}
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"$session_id"}';
select revision from public.publish_encrypted_vault_snapshot(
  $expected_revision::bigint,
  1::smallint,
  'AES-256-GCM',
  'AAAAAAAAAAAAAAAA',
  'TEST_ONLY_CIPHERTEXT',
  'AAAAAAAAAAAAAAAAAAAAAA==',
  1::smallint,
  'BBBBBBBBBBBBBBBB',
  'TEST_ONLY_WRAPPED_KEY_CIPHERTEXT_1234567890',
  'BBBBBBBBBBBBBBBBBBBBBB=='
);
SQL
}

first_revision=$(publish_sql 0 | tail -n 1)
[[ "$first_revision" == 1 ]]

if publish_sql 0 >/dev/null 2>&1; then
  printf '%s\n' 'Expected-revision conflict đã bị bỏ qua.' >&2
  exit 1
fi

second_revision=$(publish_sql 1 | tail -n 1)
[[ "$second_revision" == 2 ]]

owner_count=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select count(*) from public.encrypted_vault_snapshots;
SQL
)
[[ "$owner_count" == 1 ]]

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
delete from auth.sessions
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
SQL

revoked_count=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}';
select count(*) from public.encrypted_vault_snapshots;
SQL
)
[[ "$revoked_count" == 0 ]]

if publish_sql 2 >/dev/null 2>&1; then
  printf '%s\n' 'Phiên đã revoke vẫn publish được encrypted vault.' >&2
  exit 1
fi

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
insert into auth.sessions (id, user_id) values (
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  '11111111-1111-4111-8111-111111111111'
);
SQL

third_revision=$(publish_sql 2 cccccccc-cccc-4ccc-8ccc-cccccccccccc | tail -n 1)
[[ "$third_revision" == 3 ]]

other_count=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","session_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}';
select count(*) from public.encrypted_vault_snapshots;
SQL
)
[[ "$other_count" == 0 ]]

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL' >/dev/null 2>&1
set role anon;
set request.jwt.claims = '{}';
select * from public.publish_encrypted_vault_snapshot(
  0::bigint, 1::smallint, 'AES-256-GCM', 'AAAAAAAAAAAAAAAA', 'TEST_ONLY_CIPHERTEXT',
  'AAAAAAAAAAAAAAAAAAAAAA==', 1::smallint, 'BBBBBBBBBBBBBBBB',
  'TEST_ONLY_WRAPPED_KEY_CIPHERTEXT_1234567890', 'BBBBBBBBBBBBBBBBBBBBBB=='
);
SQL
then
  printf '%s\n' 'Anonymous đã gọi được publish function.' >&2
  exit 1
fi

register_device() {
  local user_id=$1
  local session_id=$2
  local installation_id=$3
  local name=$4
  local platform=$5
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL
set role authenticated;
set request.jwt.claims = '{"sub":"$user_id","session_id":"$session_id"}';
select registration_id from public.register_current_authenticator_device(
  '$installation_id'::uuid,
  '$name',
  '$platform'
);
SQL
}

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
insert into auth.sessions (id, user_id) values (
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  '11111111-1111-4111-8111-111111111111'
);
SQL

current_registration=$(register_device \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  10000000-0000-4000-8000-000000000001 \
  'Hyper Authenticator trên Linux' linux | tail -n 1)
other_registration=$(register_device \
  11111111-1111-4111-8111-111111111111 \
  dddddddd-dddd-4ddd-8ddd-dddddddddddd \
  10000000-0000-4000-8000-000000000002 \
  'Hyper Authenticator trên Android' android | tail -n 1)
[[ -n "$current_registration" && -n "$other_registration" ]]
[[ "$current_registration" != "$other_registration" ]]

device_list_shape=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select count(*) || ':' || count(*) filter (where is_current)
from public.list_authenticator_device_sessions();
SQL
)
[[ "$device_list_shape" == '2:1' ]]

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL' >/dev/null 2>&1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select * from public.authenticator_device_sessions;
SQL
then
  printf '%s\n' 'Authenticated role đã SELECT trực tiếp device registry.' >&2
  exit 1
fi

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL' >/dev/null 2>&1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select * from private.encrypted_vault_membership_verifiers;
SQL
then
  printf '%s\n' 'Authenticated role đã đọc server-only vault verifier.' >&2
  exit 1
fi

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<SQL >/dev/null 2>&1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select public.revoke_authenticator_device_session('$current_registration'::uuid);
SQL
then
  printf '%s\n' 'Current device session đã tự revoke qua device RPC.' >&2
  exit 1
fi

revoked_result=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select public.revoke_authenticator_device_session('$other_registration'::uuid);
SQL
)
[[ "$revoked_result" == t ]]

remaining_devices=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select count(*) from public.list_authenticator_device_sessions();
SQL
)
[[ "$remaining_devices" == 1 ]]

if publish_sql 3 dddddddd-dddd-4ddd-8ddd-dddddddddddd >/dev/null 2>&1; then
  printf '%s\n' 'Device session đã revoke vẫn publish được encrypted vault.' >&2
  exit 1
fi

other_user_registration=$(register_device \
  22222222-2222-4222-8222-222222222222 \
  bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb \
  20000000-0000-4000-8000-000000000001 \
  'Hyper Authenticator trên Windows' windows | tail -n 1)
[[ -n "$other_user_registration" ]]

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<SQL >/dev/null 2>&1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select public.revoke_authenticator_device_session('$other_user_registration'::uuid);
SQL
then
  printf '%s\n' 'User A đã revoke được device session của User B.' >&2
  exit 1
fi

other_user_devices=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","session_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}';
select count(*) from public.list_authenticator_device_sessions();
SQL
)
[[ "$other_user_devices" == 1 ]]

force_rls=$(docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select relrowsecurity and relforcerowsecurity
from pg_class
where oid = 'public.authenticator_device_sessions'::regclass;
SQL
)
[[ "$force_rls" == t ]]

ZERO_32='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
ONE_32='AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
TWO_32='AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI='
THREE_32='AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwM='
ZERO_16='AAAAAAAAAAAAAAAAAAAAAA=='

device_protocol_backfill=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select key_generation || ':' || device_wrap_version || ':' ||
       ((select count(*) from private.encrypted_vault_membership_verifiers) = 0)
from public.encrypted_vault_snapshots
where user_id = '11111111-1111-4111-8111-111111111111';
SQL
)
[[ "$device_protocol_backfill" == '1:0:true' ]]

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL' >/dev/null 2>&1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select * from public.authenticator_device_keys;
SQL
then
  printf '%s\n' 'Authenticated role đã SELECT trực tiếp device key table.' >&2
  exit 1
fi

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL' >/dev/null 2>&1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select * from public.authenticator_device_key_wraps;
SQL
then
  printf '%s\n' 'Authenticated role đã SELECT trực tiếp device wrap table.' >&2
  exit 1
fi

begin_device_key() {
  local user_id=$1
  local session_id=$2
  local installation_id=$3
  local public_key=$4
  local binding_secret=$5
  local vault_membership_verifier=$6
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL
set role authenticated;
set request.jwt.claims = '{"sub":"$user_id","session_id":"$session_id"}';
select device_key_id || '|' || device_state || '|' || key_generation
from public.begin_authenticator_device_key_enrollment(
  '$installation_id'::uuid,
  '$public_key',
  '$binding_secret',
  '$vault_membership_verifier'
);
SQL
}

publish_device_wrap() {
  local user_id=$1
  local session_id=$2
  local target_device_key_id=$3
  local binding_secret=$4
  local generation=$5
  local encapsulated_key=$6
  local ciphertext=$7
  local auth_tag=$8
  local vault_membership_verifier=$9
  local membership_proof=${10}
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL
set role authenticated;
set request.jwt.claims = '{"sub":"$user_id","session_id":"$session_id"}';
select public.publish_authenticator_device_key_wrap(
  '$target_device_key_id'::uuid,
  '$binding_secret',
  $generation::bigint,
  1::smallint,
  'DHKEM-X25519-HKDF-SHA256',
  'HKDF-SHA256',
  'AES-256-GCM',
  '$encapsulated_key',
  '$ciphertext',
  '$auth_tag',
  '$vault_membership_verifier',
  '$membership_proof'
);
SQL
}

confirm_device_key() {
  local user_id=$1
  local session_id=$2
  local device_key_id=$3
  local binding_secret=$4
  local generation=$5
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL
set role authenticated;
set request.jwt.claims = '{"sub":"$user_id","session_id":"$session_id"}';
select public.confirm_current_authenticator_device_key(
  '$device_key_id'::uuid,
  '$binding_secret',
  $generation::bigint
);
SQL
}

current_key_record=$(begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  10000000-0000-4000-8000-000000000001 \
  "$ZERO_32" "$ONE_32" "$THREE_32" | tail -n 1)
IFS='|' read -r current_device_key current_key_state current_key_generation \
  <<<"$current_key_record"
[[ -n "$current_device_key" ]]
[[ "$current_key_state" == pending ]]
[[ "$current_key_generation" == 1 ]]

current_key_again=$(begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  10000000-0000-4000-8000-000000000001 \
  "$ZERO_32" "$ONE_32" "$THREE_32" | tail -n 1)
[[ "$current_key_again" == "$current_key_record" ]]

if begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  10000000-0000-4000-8000-000000000001 \
  "$ZERO_32" "$TWO_32" "$THREE_32" >/dev/null 2>&1; then
  printf '%s\n' 'Enrollment đã thay binding secret của device key hiện có.' >&2
  exit 1
fi

binding_shape=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL | tail -n 1
select octet_length(binding_secret_hash) || ':' ||
       (encode(binding_secret_hash, 'base64') <> '$ONE_32')
from public.authenticator_device_keys
where device_key_id = '$current_device_key'::uuid;
SQL
)
[[ "$binding_shape" == '32:true' ]]

self_wrap_result=$(publish_device_wrap \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$current_device_key" "$ONE_32" 1 \
  "$ONE_32" "$TWO_32" "$ZERO_16" "$THREE_32" "$THREE_32" | tail -n 1)
[[ "$self_wrap_result" == t ]]

current_wrap_shape=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select device_state || ':' || is_current || ':' || key_generation
from public.list_authenticator_device_keys();
SQL
)
[[ "$current_wrap_shape" == 'wrapped:true:1' ]]

if confirm_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$current_device_key" "$TWO_32" 1 >/dev/null 2>&1; then
  printf '%s\n' 'Confirm đã chấp nhận binding secret sai.' >&2
  exit 1
fi

confirm_result=$(confirm_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$current_device_key" "$ONE_32" 1 | tail -n 1)
[[ "$confirm_result" == t ]]

protocol_enabled=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select key_generation || ':' || device_wrap_version
from public.encrypted_vault_snapshots
where user_id = '11111111-1111-4111-8111-111111111111';
SQL
)
[[ "$protocol_enabled" == '1:1' ]]

if publish_sql 3 cccccccc-cccc-4ccc-8ccc-cccccccccccc >/dev/null 2>&1; then
  printf '%s\n' 'Legacy publish vẫn chạy sau khi device-wrap protocol đã bật.' >&2
  exit 1
fi

publish_v2_sql() {
  local expected_revision=$1
  local expected_generation=$2
  local session_id=$3
  local binding_secret=${4:-$ONE_32}
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"$session_id"}';
select revision || ':' || key_generation || ':' || device_wrap_version
from public.publish_encrypted_vault_snapshot_v2(
  $expected_revision::bigint,
  $expected_generation::bigint,
  '$binding_secret',
  1::smallint,
  'AES-256-GCM',
  'AAAAAAAAAAAAAAAA',
  'TEST_ONLY_V2_CIPHERTEXT',
  'AAAAAAAAAAAAAAAAAAAAAA==',
  1::smallint,
  'BBBBBBBBBBBBBBBB',
  'TEST_ONLY_V2_WRAPPED_KEY_CIPHERTEXT_1234567890',
  'BBBBBBBBBBBBBBBBBBBBBB=='
);
SQL
}

if publish_v2_sql \
  3 1 cccccccc-cccc-4ccc-8ccc-cccccccccccc "$TWO_32" \
  >/dev/null 2>&1; then
  printf '%s\n' 'V2 publish đã chấp nhận binding secret sai.' >&2
  exit 1
fi

v2_publish_result=$(publish_v2_sql \
  3 1 cccccccc-cccc-4ccc-8ccc-cccccccccccc | tail -n 1)
[[ "$v2_publish_result" == '4:1:1' ]]

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
insert into auth.sessions (id, user_id) values
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
   '11111111-1111-4111-8111-111111111111'),
  ('ffffffff-ffff-4fff-8fff-ffffffffffff',
   '11111111-1111-4111-8111-111111111111'),
  ('99999999-9999-4999-8999-999999999999',
   '11111111-1111-4111-8111-111111111111');
SQL

second_registration=$(register_device \
  11111111-1111-4111-8111-111111111111 \
  eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee \
  10000000-0000-4000-8000-000000000003 \
  'Hyper Authenticator trên Android thứ hai' android | tail -n 1)
third_registration=$(register_device \
  11111111-1111-4111-8111-111111111111 \
  ffffffff-ffff-4fff-8fff-ffffffffffff \
  10000000-0000-4000-8000-000000000004 \
  'Hyper Authenticator trên iOS' ios | tail -n 1)
web_registration=$(register_device \
  11111111-1111-4111-8111-111111111111 \
  99999999-9999-4999-8999-999999999999 \
  10000000-0000-4000-8000-000000000005 \
  'Hyper Authenticator Web' web | tail -n 1)
[[ -n "$second_registration" && -n "$third_registration" && -n "$web_registration" ]]

if begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  99999999-9999-4999-8999-999999999999 \
  10000000-0000-4000-8000-000000000005 \
  "$THREE_32" "$ZERO_32" "$THREE_32" >/dev/null 2>&1; then
  printf '%s\n' 'Web session đã enroll device key native.' >&2
  exit 1
fi

second_key_record=$(begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee \
  10000000-0000-4000-8000-000000000003 \
  "$ONE_32" "$TWO_32" "$THREE_32" | tail -n 1)
IFS='|' read -r second_device_key second_key_state second_key_generation \
  <<<"$second_key_record"
[[ "$second_key_state:$second_key_generation" == 'pending:1' ]]

if publish_device_wrap \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$second_device_key" "$ONE_32" 1 \
  "$TWO_32" "$THREE_32" "$ZERO_16" "$ZERO_32" "$ONE_32" \
  >/dev/null 2>&1; then
  printf '%s\n' 'Device wrap đã chấp nhận vault membership verifier sai.' >&2
  exit 1
fi

second_wrap_result=$(publish_device_wrap \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$second_device_key" "$ONE_32" 1 \
  "$TWO_32" "$THREE_32" "$ZERO_16" "$THREE_32" "$ONE_32" | tail -n 1)
[[ "$second_wrap_result" == t ]]

if confirm_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$second_device_key" "$TWO_32" 1 >/dev/null 2>&1; then
  printf '%s\n' 'Source device đã confirm wrap thay target device.' >&2
  exit 1
fi

second_visible_wrap=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
select count(*) || ':' || count(*) filter (
  where is_current and device_state = 'wrapped' and key_generation = 1
)
from public.list_authenticator_device_keys();
SQL
)
[[ "$second_visible_wrap" == '2:1' ]]

second_confirm=$(confirm_device_key \
  11111111-1111-4111-8111-111111111111 \
  eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee \
  "$second_device_key" "$TWO_32" 1 | tail -n 1)
[[ "$second_confirm" == t ]]

third_key_record=$(begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  ffffffff-ffff-4fff-8fff-ffffffffffff \
  10000000-0000-4000-8000-000000000004 \
  "$TWO_32" "$THREE_32" "$THREE_32" | tail -n 1)
IFS='|' read -r third_device_key third_key_state third_key_generation \
  <<<"$third_key_record"
[[ "$third_key_state:$third_key_generation" == 'pending:1' ]]

if publish_device_wrap \
  11111111-1111-4111-8111-111111111111 \
  ffffffff-ffff-4fff-8fff-ffffffffffff \
  "$third_device_key" "$THREE_32" 1 \
  "$THREE_32" "$ZERO_32" "$ZERO_16" "$ZERO_32" "$TWO_32" \
  >/dev/null 2>&1; then
  printf '%s\n' 'Pending self-wrap không biết DEK verifier vẫn được chấp nhận.' >&2
  exit 1
fi

third_wrap_result=$(publish_device_wrap \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$third_device_key" "$ONE_32" 1 \
  "$THREE_32" "$ZERO_32" "$ZERO_16" "$THREE_32" "$TWO_32" | tail -n 1)
[[ "$third_wrap_result" == t ]]

if publish_v2_sql \
  4 1 ffffffff-ffff-4fff-8fff-ffffffffffff "$THREE_32" \
  >/dev/null 2>&1; then
  printf '%s\n' 'Device chưa confirm đã publish được snapshot v2.' >&2
  exit 1
fi

printf -v survivor_wrap \
  '[{"device_key_id":"%s","key_generation":2,"format_version":1,"kem":"DHKEM-X25519-HKDF-SHA256","kdf":"HKDF-SHA256","aead":"AES-256-GCM","encapsulated_key":"%s","ciphertext":"%s","auth_tag":"%s","membership_proof":"%s"}]' \
  "$current_device_key" "$ZERO_32" "$ONE_32" "$ZERO_16" "$TWO_32"

rotate_device_keys() {
  local binding_secret=$1
  local excluded_array=$2
  local wraps_json=$3
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"cccccccc-cccc-4ccc-8ccc-cccccccccccc"}';
select revision || ':' || key_generation
from public.rotate_encrypted_vault_device_keys(
  4::bigint,
  1::bigint,
  '$binding_secret',
  1::smallint,
  'AES-256-GCM',
  'ROTATION_NONCE_01',
  'TEST_ONLY_ROTATED_CIPHERTEXT',
  'ROTATION_AUTH_TAG_01',
  1::smallint,
  'ROTATION_WRAPPED_KEY_NONCE',
  'TEST_ONLY_ROTATED_WRAPPED_KEY_CIPHERTEXT_1234567890',
  'ROTATION_WRAPPED_KEY_TAG',
  '$TWO_32',
  '$wraps_json'::jsonb,
  $excluded_array
);
SQL
}

if rotate_device_keys "$ONE_32" 'array[]::uuid[]' \
  "$survivor_wrap" >/dev/null 2>&1; then
  printf '%s\n' 'Rotation đã chấp nhận wrap set thiếu active device.' >&2
  exit 1
fi

if rotate_device_keys "$TWO_32" \
  "array['$second_device_key'::uuid]" "$survivor_wrap" >/dev/null 2>&1; then
  printf '%s\n' 'Rotation đã chấp nhận binding secret sai.' >&2
  exit 1
fi

pre_rotation_state=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL | tail -n 1
select revision || ':' || key_generation || ':' ||
       (select count(*) from auth.sessions where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')
from public.encrypted_vault_snapshots
where user_id = '11111111-1111-4111-8111-111111111111';
SQL
)
[[ "$pre_rotation_state" == '4:1:1' ]]

rotation_result=$(rotate_device_keys "$ONE_32" \
  "array['$second_device_key'::uuid]" "$survivor_wrap" | tail -n 1)
[[ "$rotation_result" == '5:2' ]]

post_rotation_state=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL | tail -n 1
select
  snapshot.revision || ':' || snapshot.key_generation || ':' ||
  (select state from public.authenticator_device_keys where device_key_id = '$current_device_key'::uuid) || ':' ||
  (select key_generation from public.authenticator_device_key_wraps where device_key_id = '$current_device_key'::uuid) || ':' ||
  (select state from public.authenticator_device_keys where device_key_id = '$second_device_key'::uuid) || ':' ||
  (select state from public.authenticator_device_keys where device_key_id = '$third_device_key'::uuid) || ':' ||
  (select count(*) from public.authenticator_device_key_wraps where device_key_id = '$third_device_key'::uuid) || ':' ||
  (select count(*) from auth.sessions where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee')
from public.encrypted_vault_snapshots as snapshot
where snapshot.user_id = '11111111-1111-4111-8111-111111111111';
SQL
)
[[ "$post_rotation_state" == '5:2:active:2:revoked:pending:0:0' ]]

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL' >/dev/null 2>&1
set role authenticated;
set request.jwt.claims = '{"sub":"11111111-1111-4111-8111-111111111111","session_id":"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"}';
select count(*) from public.list_authenticator_device_keys();
SQL
then
  printf '%s\n' 'Session của device bị crypto-revoke vẫn gọi được RPC.' >&2
  exit 1
fi

post_rotation_publish=$(publish_v2_sql \
  5 2 cccccccc-cccc-4ccc-8ccc-cccccccccccc | tail -n 1)
[[ "$post_rotation_publish" == '6:2:1' ]]

if begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  10000000-0000-4000-8000-000000000001 \
  "$ONE_32" "$TWO_32" "$ZERO_32" >/dev/null 2>&1; then
  printf '%s\n' 'Lost-key replacement đã chấp nhận DEK verifier sai.' >&2
  exit 1
fi

replacement_record=$(begin_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  10000000-0000-4000-8000-000000000001 \
  "$ONE_32" "$TWO_32" "$TWO_32" | tail -n 1)
IFS='|' read -r replacement_device_key replacement_state replacement_generation \
  <<<"$replacement_record"
[[ "$replacement_state:$replacement_generation" == 'pending:2' ]]
[[ "$replacement_device_key" != "$current_device_key" ]]

replacement_wrap=$(publish_device_wrap \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$replacement_device_key" "$TWO_32" 2 \
  "$ONE_32" "$TWO_32" "$ZERO_16" "$TWO_32" "$THREE_32" | tail -n 1)
[[ "$replacement_wrap" == t ]]
replacement_confirm=$(confirm_device_key \
  11111111-1111-4111-8111-111111111111 \
  cccccccc-cccc-4ccc-8ccc-cccccccccccc \
  "$replacement_device_key" "$TWO_32" 2 | tail -n 1)
[[ "$replacement_confirm" == t ]]

replacement_state_shape=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<SQL | tail -n 1
select
  (select state from public.authenticator_device_keys where device_key_id = '$current_device_key'::uuid) || ':' ||
  (select state from public.authenticator_device_keys where device_key_id = '$replacement_device_key'::uuid) || ':' ||
  (select device_key_id = '$replacement_device_key'::uuid from public.authenticator_device_sessions where session_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc') || ':' ||
  (select key_generation from public.authenticator_device_key_wraps where device_key_id = '$replacement_device_key'::uuid);
SQL
)
[[ "$replacement_state_shape" == 'revoked:active:true:2' ]]

other_user_device_keys=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
set role authenticated;
set request.jwt.claims = '{"sub":"22222222-2222-4222-8222-222222222222","session_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"}';
select count(*) from public.list_authenticator_device_keys();
SQL
)
[[ "$other_user_device_keys" == 0 ]]

device_key_force_rls=$(docker exec -i "$CONTAINER" \
  psql -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select bool_and(relrowsecurity and relforcerowsecurity)
from pg_class
where oid in (
  'public.authenticator_device_keys'::regclass,
  'public.authenticator_device_key_wraps'::regclass
);
SQL
)
[[ "$device_key_force_rls" == t ]]

printf '%s\n' \
  'Encrypted vault migration pass: verifier-gated lost-key recovery, active-device binding, exact wrap rotation và crypto revoke.'
