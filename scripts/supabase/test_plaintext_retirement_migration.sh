#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CREATE_MIGRATION="$ROOT/supabase/migrations/20260717163000_create_synced_accounts.sql"
RETIRE_MIGRATION="$ROOT/supabase/migrations/20260722110000_retire_plaintext_synced_accounts.sql"
IMAGE=${POSTGRES_TEST_IMAGE:-postgres:17-alpine@sha256:979c4379dd698aba0b890599a6104e082035f98ef31d9b9291ec22f2b13059ca}
CONTAINER="hyper-auth-plaintext-retirement-test-$$"

cleanup() {
  docker container rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run --detach --name "$CONTAINER" \
  --env POSTGRES_PASSWORD=TEST_ONLY_PASSWORD \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=128m \
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
create function auth.uid() returns uuid
language sql stable
as $$ select null::uuid $$;
grant usage on schema auth, public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
insert into auth.users (id)
values ('11111111-1111-4111-8111-111111111111');
SQL

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  <"$CREATE_MIGRATION"

writer_log=$(mktemp "${TMPDIR:-/tmp}/hyper-auth-plaintext-writer.XXXXXX")
cleanup_writer_log() {
  find "$writer_log" -maxdepth 0 -type f -delete 2>/dev/null || true
}
trap 'cleanup_writer_log; cleanup' EXIT INT TERM

# Keep a legacy INSERT uncommitted while retirement starts. A correct
# migration waits for the RowExclusiveLock, then observes the committed row
# under its own AccessExclusiveLock and aborts. A count-before-lock
# implementation would see zero, wait only at DROP TABLE, then lose the row.
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  >"$writer_log" 2>&1 <<'SQL' &
begin;
insert into public.synced_accounts (
  user_id, account_id, issuer, account_name, secret_key
) values (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'TEST ONLY',
  'test@example.invalid',
  'TEST_ONLY_NOT_A_SECRET'
);
select pg_sleep(2);
commit;
SQL
writer_pid=$!

writer_lock_ready=false
for _ in {1..40}; do
  writer_lock=$(docker exec -i "$CONTAINER" psql \
    -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select exists (
  select 1
  from pg_locks
  where relation = 'public.synced_accounts'::regclass
    and mode = 'RowExclusiveLock'
    and granted
);
SQL
  )
  if [[ "$writer_lock" == t ]]; then
    writer_lock_ready=true
    break
  fi
  sleep 0.05
done
if [[ "$writer_lock_ready" != true ]]; then
  printf '%s\n' 'Không tạo được concurrent legacy writer cho regression.' >&2
  exit 1
fi

if retirement_error=$(docker exec -i "$CONTAINER" psql -X \
  -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -U postgres \
  <"$RETIRE_MIGRATION" 2>&1); then
  printf '%s\n' \
    'Migration retirement đã drop bảng dù còn plaintext row.' >&2
  exit 1
fi
if [[ "$retirement_error" != *'55000: plaintext_legacy_rows_present'* ]]; then
  printf '%s\n' \
    'Migration retirement fail nhưng không trả đúng SQLSTATE/message bảo vệ data.' >&2
  exit 1
fi
wait "$writer_pid"

rollback_shape=$(docker exec -i "$CONTAINER" psql \
  -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select to_regclass('public.synced_accounts') is not null
       and (select count(*) from public.synced_accounts) = 1;
SQL
)
[[ "$rollback_shape" == t ]]

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
delete from public.synced_accounts;
SQL
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  <"$RETIRE_MIGRATION"

retired=$(docker exec -i "$CONTAINER" psql \
  -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select to_regclass('public.synced_accounts') is null;
SQL
)
[[ "$retired" == t ]]

# Re-application must stay safe for rebuilt/fresh environments.
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  <"$RETIRE_MIGRATION" >/dev/null

# A table created after a completed absent-table replay must not be removed by
# any deferred/unconditional DROP outside the guarded DO branch.
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
create role migration_owner login;
create table public.synced_accounts (sentinel text not null);
insert into public.synced_accounts values ('TEST_ONLY_RECREATED_AFTER_REPLAY');
alter table public.synced_accounts owner to migration_owner;
alter table public.synced_accounts enable row level security;
alter table public.synced_accounts force row level security;
create policy hide_every_row on public.synced_accounts using (false);
SQL

if rls_error=$(docker exec -i "$CONTAINER" psql -X \
  -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -U migration_owner -d postgres \
  <"$RETIRE_MIGRATION" 2>&1); then
  printf '%s\n' \
    'Migration retirement đã dùng policy-filtered count và drop dữ liệu ẩn bởi RLS.' >&2
  exit 1
fi
if [[ "$rls_error" != *'row-level security policy'* ]]; then
  printf '%s\n' \
    'Migration retirement không fail closed rõ ràng cho operator thiếu BYPASSRLS.' >&2
  exit 1
fi

recreated_shape=$(docker exec -i "$CONTAINER" psql \
  -X -A -t -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select to_regclass('public.synced_accounts') is not null
       and (select count(*) from public.synced_accounts) = 1;
SQL
)
[[ "$recreated_shape" == t ]]

cleanup_writer_log

printf '%s\n' \
  'Plaintext retirement migration pass: exact SQLSTATE, concurrent writer/RLS fail-closed, rollback intact, empty drop và replay-safe idempotence.'
