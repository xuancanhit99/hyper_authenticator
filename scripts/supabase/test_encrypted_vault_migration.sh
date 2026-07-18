#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MIGRATIONS=(
  "$ROOT/supabase/migrations/20260718190000_create_encrypted_vault_snapshots.sql"
  "$ROOT/supabase/migrations/20260718230000_enforce_active_vault_sessions.sql"
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

printf '%s\n' \
  'Encrypted vault migration pass: atomic revision, conflict, owner RLS và active-session enforcement.'
