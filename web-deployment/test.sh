#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

sh -n web-deployment/docker-entrypoint.sh
grep -Fq 'access_log off;' web-deployment/nginx.conf
grep -Fq 'Content-Security-Policy' web-deployment/nginx-site.conf.template
grep -Fq 'camera=(self)' web-deployment/nginx-site.conf.template
grep -Fq 'https://cdn.jsdelivr.net' web-deployment/nginx-site.conf.template
grep -Fq 'https://fastly.jsdelivr.net' web-deployment/nginx-site.conf.template
grep -Fq 'https://fonts.gstatic.com' web-deployment/nginx-site.conf.template
grep -Fq 'Strict-Transport-Security' web-deployment/nginx-site.conf.template
grep -Fq 'try_files $uri $uri/ /index.html' web-deployment/nginx-site.conf.template

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  printf '%s\n' 'Static Web-serving checks pass; bỏ qua container vì Docker không khả dụng.'
  exit 0
fi

image="hyper-authenticator-web:test"
name="hyper-authenticator-web-test-$$"

cleanup() {
  docker container rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

bash web-deployment/build-image.sh "$image"

if docker run --rm "$image" >/dev/null 2>&1; then
  printf '%s\n' 'Container đã chấp nhận cấu hình thiếu.' >&2
  exit 1
fi

if docker run --rm \
  --env SUPABASE_URL=http://supabase.test.invalid \
  "$image" >/dev/null 2>&1; then
  printf '%s\n' 'Container đã chấp nhận HTTP Supabase URL.' >&2
  exit 1
fi

if docker run --rm \
  --env SUPABASE_URL=https://user@supabase.test.invalid \
  "$image" >/dev/null 2>&1; then
  printf '%s\n' 'Container đã chấp nhận Supabase URL có user info.' >&2
  exit 1
fi

docker run --rm \
  --env SUPABASE_URL=https://supabase.test.invalid/ \
  "$image" nginx -t >/dev/null

docker run --detach --name "$name" \
  --read-only \
  --tmpfs /tmp:size=1m,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --env SUPABASE_URL=https://supabase.test.invalid \
  "$image" >/dev/null

attempt=0
until [[ "$(docker inspect --format '{{.State.Health.Status}}' "$name")" == healthy ]]; do
  attempt=$((attempt + 1))
  if [[ "$attempt" -ge 20 ]]; then
    docker logs "$name" >&2
    exit 1
  fi
  sleep 1
done

root_headers=$(docker exec "$name" wget -S -q -O /dev/null \
  http://127.0.0.1:8080/ 2>&1)
printf '%s' "$root_headers" | grep -Fiq 'Cache-Control: no-store'
printf '%s' "$root_headers" | grep -Fiq 'Content-Security-Policy:'
printf '%s' "$root_headers" | grep -Fiq 'https://supabase.test.invalid'
printf '%s' "$root_headers" | grep -Fiq 'wss://supabase.test.invalid'
printf '%s' "$root_headers" | grep -Fiq 'Permissions-Policy: camera=(self)'
printf '%s' "$root_headers" | grep -Fiq 'Strict-Transport-Security:'

js_headers=$(docker exec "$name" wget -S -q -O /dev/null \
  http://127.0.0.1:8080/flutter_bootstrap.js 2>&1)
printf '%s' "$js_headers" | grep -Fiq \
  'Cache-Control: public, max-age=0, must-revalidate'

docker exec "$name" wget -q -O - http://127.0.0.1:8080/healthz |
  grep -qx healthy
docker exec "$name" wget -q -O - http://127.0.0.1:8080/settings |
  grep -Fq '<title>Hyper Authenticator</title>'

if docker exec "$name" wget -q -O /dev/null \
  http://127.0.0.1:8080/.env 2>/dev/null; then
  printf '%s\n' 'Container phục vụ dotfile.' >&2
  exit 1
fi

docker exec "$name" wget -q -O /dev/null \
  'http://127.0.0.1:8080/?token=WEB_LOG_SECRET_TEST_ONLY'
if docker logs "$name" 2>&1 | grep -Fq 'WEB_LOG_SECRET_TEST_ONLY'; then
  printf '%s\n' 'Query material xuất hiện trong Web container log.' >&2
  exit 1
fi

if docker exec "$name" sh -c \
  "find /usr/share/nginx/html -name '.env' -o -name '*.env' | grep -q ."; then
  printf '%s\n' 'Production image chứa file môi trường.' >&2
  exit 1
fi

printf '%s\n' 'Flutter Web serving contract pass: CSP, cache, SPA, read-only và no-log.'
