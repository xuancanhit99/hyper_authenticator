#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ACCOUNT_SYNC_MIGRATION="$ROOT/supabase/migrations/20260804000000_create_account_managed_sync.sql"
REALTIME_MIGRATION="$ROOT/supabase/migrations/20260805000000_add_account_sync_realtime_signal.sql"
REALTIME_AUTH_FIX_MIGRATION="$ROOT/supabase/migrations/20260805010000_fix_account_sync_realtime_authorization.sql"
IMAGE=${SUPABASE_POSTGRES_TEST_IMAGE:-supabase/postgres:17.6.1.136@sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00}
CONTAINER="hyper-auth-account-sync-postgres-test-$$"
printf -v TEST_PGSODIUM_KEY '%064d' 0

cleanup() {
  docker container rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker run --detach --name "$CONTAINER" \
  --env POSTGRES_PASSWORD=TEST_ONLY_PASSWORD \
  --env PGSODIUM_KEY="$TEST_PGSODIUM_KEY" \
  --tmpfs /var/lib/postgresql/data:rw,noexec,nosuid,size=512m \
  "$IMAGE" >/dev/null

attempt=0
until docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [[ "$attempt" -ge 60 ]]; then
    docker logs "$CONTAINER" >&2
    exit 1
  fi
  sleep 1
done

# Realtime service migrations không nằm trong Postgres image fixture. Dựng
# đúng surface mà production 2.102.3 cung cấp để test policy/trigger; migration
# ứng dụng vẫn fail closed nếu object này thiếu trên target thật.
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 \
  -U supabase_admin -d postgres <<'SQL'
drop schema if exists realtime cascade;
create schema realtime;
grant usage on schema realtime to anon, authenticated;
create table realtime.messages (
  topic text not null,
  extension text not null,
  payload jsonb,
  event text,
  private boolean,
  updated_at timestamp without time zone not null default now(),
  inserted_at timestamp without time zone not null default now(),
  id uuid primary key default gen_random_uuid(),
  binary_payload bytea
);
alter table realtime.messages enable row level security;
grant select, insert on realtime.messages to anon, authenticated;
create function realtime.topic()
returns text
language sql
stable
as $$
  select nullif(current_setting('realtime.topic', true), '')::text;
$$;
create function realtime.send(
  payload jsonb,
  event text,
  topic text,
  private boolean default true
)
returns void
language plpgsql
as $$
declare
  generated_id uuid := gen_random_uuid();
  final_payload jsonb;
begin
  final_payload := case
    when payload ? 'id' then payload
    else jsonb_set(payload, '{id}', to_jsonb(generated_id))
  end;
  perform set_config('realtime.topic', topic, true);
  insert into realtime.messages (
    id, payload, event, topic, private, extension
  ) values (
    generated_id, final_payload, event, topic, private, 'broadcast'
  );
end;
$$;
SQL

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

-- Current production contract fixture: migration mới phải loại bỏ đúng Minimal
-- E2EE table/RPC nhưng không đụng auth.users.
create table public.encrypted_vault_snapshots (
  user_id uuid primary key references auth.users (id),
  revision bigint not null
);
create function public.publish_encrypted_vault_snapshot(
  bigint, smallint, text, text, text, text, smallint, text, text, text
) returns void language sql as $$ select $$;
SQL

docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  <"$ACCOUNT_SYNC_MIGRATION"
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  <"$REALTIME_MIGRATION"
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  <"$REALTIME_AUTH_FIX_MIGRATION"

rpc_sql() {
  local user_id=$1
  local sql=$2
  docker exec -i "$CONTAINER" psql -X -A -t -v ON_ERROR_STOP=1 \
    -U postgres <<SQL
set role authenticated;
set request.jwt.claim.sub = '$user_id';
$sql
SQL
}

payload_sql="jsonb_build_object(
  'issuer', 'TEST ONLY',
  'accountName', 'not-a-real-account@example.test',
  'secretKey', repeat('A', 32),
  'algorithm', 'SHA1',
  'digits', 6,
  'period', 30
)"

revision=$(rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select revision from public.upsert_authenticator_account(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0, $payload_sql
  );" | tail -n 1)
[[ "$revision" == 1 ]]

signal_payload_ok=$(docker exec -i "$CONTAINER" psql -X -A -t \
  -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select count(*) = 1
from realtime.messages
where topic = 'account-sync:11111111-1111-4111-8111-111111111111'
  and event = 'account-sync-changed'
  and extension = 'broadcast'
  and private is true
  and payload ->> 'version' = '1'
  and payload ? 'id'
  and payload - 'version' - 'id' = '{}'::jsonb
  and payload::text not like '%TEST ONLY%'
  and payload::text not like '%not-a-real-account%'
  and payload::text not like '%AAAAAAAAAAAAAAAA%';
SQL
)
[[ "$signal_payload_ok" == t ]]

# Realtime 2.102.3 authorizes a private join with a temporary probe containing
# only topic + extension. Its private field is NULL; the SELECT policy must
# accept that owner probe while still rejecting another user's topic.
authorization_probe_ok=$(docker exec -i "$CONTAINER" psql -X -A -t \
  -v ON_ERROR_STOP=1 -U postgres <<'SQL' | grep '^probe_' | tail -n 2
begin;
insert into realtime.messages (id, topic, extension)
values (
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'account-sync:11111111-1111-4111-8111-111111111111',
  'broadcast'
);
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',
  true
);
select set_config(
  'realtime.topic',
  'account-sync:11111111-1111-4111-8111-111111111111',
  true
);
select 'probe_owner=' || count(*)
from realtime.messages
where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
select set_config(
  'request.jwt.claim.sub',
  '22222222-2222-4222-8222-222222222222',
  true
);
select 'probe_other=' || count(*)
from realtime.messages
where id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
rollback;
SQL
)
[[ "$authorization_probe_ok" == $'probe_owner=1\nprobe_other=0' ]]

owner_signal_count=$(rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select set_config(
     'realtime.topic',
     'account-sync:11111111-1111-4111-8111-111111111111',
     false
   );
   select count(*) from realtime.messages
   where extension = 'broadcast';" | tail -n 1)
[[ "$owner_signal_count" == 1 ]]

cross_user_signal_count=$(rpc_sql 22222222-2222-4222-8222-222222222222 \
  "select set_config(
     'realtime.topic',
     'account-sync:11111111-1111-4111-8111-111111111111',
     false
   );
   select count(*) from realtime.messages
   where extension = 'broadcast';" | tail -n 1)
[[ "$cross_user_signal_count" == 0 ]]

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 \
  -U postgres >/dev/null 2>&1 <<'SQL'
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
select set_config(
  'realtime.topic',
  'account-sync:11111111-1111-4111-8111-111111111111',
  false
);
insert into realtime.messages (payload, event, topic, private, extension)
values (
  '{"version": 1}', 'account-sync-changed',
  'account-sync:11111111-1111-4111-8111-111111111111', true, 'broadcast'
);
SQL
then
  printf '%s\n' 'Authenticated client đã tự phát được Realtime signal.' >&2
  exit 1
fi

if rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select * from public.upsert_authenticator_account(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0, $payload_sql
  );" >/dev/null 2>&1; then
  printf '%s\n' 'CAS conflict đã bị bỏ qua.' >&2
  exit 1
fi

if rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select * from public.upsert_authenticator_account(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 0,
    jsonb_set($payload_sql, '{period}', '30.5'::jsonb)
  );" >/dev/null 2>&1; then
  printf '%s\n' 'Payload period phân số đã được nhận.' >&2
  exit 1
fi

revision=$(rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select revision from public.upsert_authenticator_account(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 1,
    jsonb_set($payload_sql, '{issuer}', to_jsonb('TEST EDITED'::text))
  );" | tail -n 1)
[[ "$revision" == 2 ]]

owner_payload_ok=$(rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select count(*) = 1
   from public.list_authenticator_accounts()
   where account_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and deleted_at is null
     and payload ->> 'issuer' = 'TEST EDITED'
     and payload ->> 'secretKey' = repeat('A', 32);" | tail -n 1)
[[ "$owner_payload_ok" == t ]]

other_count=$(rpc_sql 22222222-2222-4222-8222-222222222222 \
  "select count(*) from public.list_authenticator_accounts();" | tail -n 1)
[[ "$other_count" == 0 ]]

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 \
  -U postgres >/dev/null 2>&1 <<'SQL'
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
select * from public.authenticator_accounts;
SQL
then
  printf '%s\n' 'Authenticated client đã đọc trực tiếp sync table.' >&2
  exit 1
fi

if docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 \
  -U postgres >/dev/null 2>&1 <<'SQL'
set role anon;
select * from public.list_authenticator_accounts();
SQL
then
  printf '%s\n' 'Anonymous đã gọi được account sync RPC.' >&2
  exit 1
fi

if rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select * from public.upsert_authenticator_account(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 0,
    jsonb_set($payload_sql, '{algorithm}', to_jsonb('MD5'::text))
  );" >/dev/null 2>&1; then
  printf '%s\n' 'Payload algorithm không hợp lệ đã được nhận.' >&2
  exit 1
fi

deleted_revision=$(rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select revision from public.delete_authenticator_account(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 2
  );" | tail -n 1)
[[ "$deleted_revision" == 3 ]]

tombstone_ok=$(rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select count(*) = 1
   from public.list_authenticator_accounts()
   where account_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     and revision = 3
     and deleted_at is not null
     and payload is null;" | tail -n 1)
[[ "$tombstone_ok" == t ]]

if rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select * from public.upsert_authenticator_account(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 3, $payload_sql
  );" >/dev/null 2>&1; then
  printf '%s\n' 'Tombstone đã bị revive bởi stale client.' >&2
  exit 1
fi

# Tạo một live record khác để chứng minh table/backup giữ ciphertext, không giữ
# plaintext payload; chỉ authenticated RPC mới đọc decrypted view.
rpc_sql 11111111-1111-4111-8111-111111111111 \
  "select revision from public.upsert_authenticator_account(
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 0, $payload_sql
  );" >/dev/null

vault_at_rest_ok=$(docker exec -i "$CONTAINER" psql -X -A -t \
  -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select count(*) = 1
from vault.secrets as secret
join public.authenticator_accounts as account
  on account.vault_secret_id = secret.id
where account.account_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
  and secret.secret not like '%not-a-real-account%'
  and secret.secret not like '%AAAAAAAAAAAAAAAA%';
SQL
)
[[ "$vault_at_rest_ok" == t ]]

# Auth user cascade phải xóa live row và Vault secret tương ứng, không để orphan.
rpc_sql 22222222-2222-4222-8222-222222222222 \
  "select revision from public.upsert_authenticator_account(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 0, $payload_sql
  );" >/dev/null
vault_before_user_delete=$(docker exec -i "$CONTAINER" psql -X -A -t \
  -v ON_ERROR_STOP=1 -U postgres \
  -c 'select count(*) from vault.secrets;' | tail -n 1)
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres \
  -c "delete from auth.users where id = '22222222-2222-4222-8222-222222222222';" \
  >/dev/null
vault_after_user_delete=$(docker exec -i "$CONTAINER" psql -X -A -t \
  -v ON_ERROR_STOP=1 -U postgres \
  -c 'select count(*) from vault.secrets;' | tail -n 1)
[[ "$vault_after_user_delete" -eq $((vault_before_user_delete - 1)) ]]
user_cleanup_ok=$(docker exec -i "$CONTAINER" psql -X -A -t \
  -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select count(*) = 0
from public.authenticator_accounts
where user_id = '22222222-2222-4222-8222-222222222222';
SQL
)
[[ "$user_cleanup_ok" == t ]]

catalog_ok=$(docker exec -i "$CONTAINER" psql -X -A -t \
  -v ON_ERROR_STOP=1 -U postgres <<'SQL' | tail -n 1
select
  (select relrowsecurity and relforcerowsecurity
   from pg_class
   where oid = 'public.authenticator_accounts'::regclass)
  and not has_table_privilege(
    'authenticated', 'public.authenticator_accounts',
    'select,insert,update,delete'
  )
  and has_function_privilege(
    'authenticated', 'public.list_authenticator_accounts()', 'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.upsert_authenticator_account(uuid,bigint,jsonb)', 'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.delete_authenticator_account(uuid,bigint)', 'execute'
  )
  and not has_function_privilege(
    'anon', 'public.list_authenticator_accounts()', 'execute'
  )
  and (select prosecdef from pg_proc where oid =
    'public.list_authenticator_accounts()'::regprocedure)
  and (select prosecdef from pg_proc where oid =
    'public.upsert_authenticator_account(uuid,bigint,jsonb)'::regprocedure)
  and (select prosecdef from pg_proc where oid =
    'public.delete_authenticator_account(uuid,bigint)'::regprocedure)
  and (select prosecdef from pg_proc where oid =
    'private.broadcast_account_sync_change()'::regprocedure)
  and exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.authenticator_accounts'::regclass
      and tgname = 'broadcast_account_sync_change'
      and not tgisinternal
  )
  and exists (
    select 1
    from pg_policy
    where polrelid = 'realtime.messages'::regclass
      and polname = 'account_sync_receive_own_broadcast'
      and polcmd = 'r'
  )
  and (
    select pg_get_expr(polqual, polrelid) not ilike '%private%'
    from pg_policy
    where polrelid = 'realtime.messages'::regclass
      and polname = 'account_sync_receive_own_broadcast'
  )
  and not exists (
    select 1
    from pg_policy
    where polrelid = 'realtime.messages'::regclass
      and polcmd = 'a'
      and 'authenticated'::regrole = any (polroles)
  )
  and not exists (
    select 1
    from pg_publication_tables
    where schemaname = 'public'
      and tablename = 'authenticator_accounts'
  )
  and to_regclass('public.encrypted_vault_snapshots') is null
  and to_regprocedure(
    'public.publish_encrypted_vault_snapshot(bigint,smallint,text,text,text,text,smallint,text,text,text)'
  ) is null;
SQL
)
[[ "$catalog_ok" == t ]]

printf '%s\n' \
  'Account-managed sync migration pass: Vault/RPC/CAS/tombstone và private credential-free Realtime signal.'
