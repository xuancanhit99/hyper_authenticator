#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$root"

sh -n docker-entrypoint.sh
node --check script.js
node script.test.js

if grep -REn 'console\.(log|debug|info|warn|error)|access_log[[:space:]]+on' script.js nginx.conf nginx-site.conf.template; then
  printf '%s\n' 'Phát hiện logging không được phép.' >&2
  exit 1
fi

grep -Fq '@supabase/supabase-js@2.110.7/' index.html
grep -Fq 'integrity="sha384-BmlQlKlDvXvKoxkn5OQuUo/aJQCTXeB+Kls6EccBmG4Kf8AXvp89RtO9MtPxP/r5"' index.html
grep -Fq 'Cache-Control "no-store' nginx-site.conf.template
grep -Fq 'Content-Security-Policy' nginx-site.conf.template
grep -Fq 'access_log off;' nginx.conf
grep -Fq '{{ .RedirectTo }}#token_hash={{ .TokenHash }}&amp;type=recovery' \
  email-templates/recovery.html

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  printf '%s\n' 'Static checks pass; bỏ qua container checks vì Docker daemon không khả dụng.'
  exit 0
fi

image="hyper-authenticator-reset-password:test"
name="hyper-authenticator-reset-password-test-$$"

cleanup() {
  docker container rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker build --tag "$image" .

if docker run --rm "$image" >/dev/null 2>&1; then
  printf '%s\n' 'Container đã chấp nhận cấu hình thiếu.' >&2
  exit 1
fi

if docker run --rm \
  --env SUPABASE_URL=http://supabase.test.invalid \
  --env SUPABASE_PUBLISHABLE_KEY=sb_publishable_TEST_ONLY_0000000000000000 \
  "$image" >/dev/null 2>&1; then
  printf '%s\n' 'Container đã chấp nhận Supabase URL không dùng HTTPS.' >&2
  exit 1
fi

if docker run --rm \
  --env SUPABASE_URL=https://supabase.test.invalid \
  --env SUPABASE_PUBLISHABLE_KEY=sb_secret_TEST_ONLY_00000000000000000000 \
  "$image" >/dev/null 2>&1; then
  printf '%s\n' 'Container đã chấp nhận server secret.' >&2
  exit 1
fi

if docker run --rm \
  --env SUPABASE_URL=https://supabase.test.invalid \
  --env SUPABASE_PUBLISHABLE_KEY=eyJ0eXAiOiJKV1QifQ.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.TEST_ONLY \
  "$image" >/dev/null 2>&1; then
  printf '%s\n' 'Container đã chấp nhận legacy service-role JWT.' >&2
  exit 1
fi

docker run --detach --name "$name" \
  --read-only \
  --tmpfs /tmp:size=1m,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --env SUPABASE_URL=https://supabase.test.invalid \
  --env SUPABASE_PUBLISHABLE_KEY=sb_publishable_TEST_ONLY_0000000000000000 \
  "$image" >/dev/null

attempt=0
until [ "$(docker inspect --format '{{.State.Health.Status}}' "$name")" = healthy ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 20 ]; then
    docker logs "$name" >&2
    exit 1
  fi
  sleep 1
done

headers=$(docker exec "$name" wget -S -q -O /dev/null http://127.0.0.1:8080/ 2>&1)
printf '%s' "$headers" | grep -Fiq 'Cache-Control: no-store'
printf '%s' "$headers" | grep -Fiq 'Content-Security-Policy:'
docker exec "$name" wget -q -O - http://127.0.0.1:8080/healthz | grep -qx healthy
docker exec "$name" wget -q -O - \
  http://127.0.0.1:8080/email-templates/recovery.html \
  | grep -Fq '{{ .TokenHash }}'

env_config=$(docker exec "$name" wget -q -O - http://127.0.0.1:8080/env-config.js)
encoded_url=$(printf '%s' 'https://supabase.test.invalid' | base64 | tr -d '\n')
encoded_key=$(printf '%s' 'sb_publishable_TEST_ONLY_0000000000000000' | base64 | tr -d '\n')
printf '%s' "$env_config" | grep -Fq "atob('$encoded_url')"
printf '%s' "$env_config" | grep -Fq "atob('$encoded_key')"

docker exec "$name" wget -q -O /dev/null \
  'http://127.0.0.1:8080/?code=RECOVERY_MATERIAL_TEST_ONLY'
if docker logs "$name" 2>&1 | grep -Fq 'RECOVERY_MATERIAL_TEST_ONLY'; then
  printf '%s\n' 'Recovery material xuất hiện trong container log.' >&2
  exit 1
fi

if docker run --rm --entrypoint sh "$image" -c 'test -e /usr/share/nginx/html/.env'; then
  printf '%s\n' 'Image chứa file .env.' >&2
  exit 1
fi

printf '%s\n' 'Static và container checks pass.'
