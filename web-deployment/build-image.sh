#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

IMAGE=${1:-hyper-authenticator-web:test}

if [[ ! -f build/web/index.html || ! -f build/web/flutter_bootstrap.js ]]; then
  printf '%s\n' \
    'Thiếu build/web. Chạy scripts/agent/build.sh web [env-file] trước.' >&2
  exit 66
fi

if find build/web -name '.env' -o -name '*.env' | grep -q .; then
  printf '%s\n' 'Web artifact chứa file môi trường; từ chối tạo image.' >&2
  exit 1
fi

if find build/web -name '*.map' | grep -q .; then
  printf '%s\n' 'Web artifact chứa source map; từ chối tạo production image.' >&2
  exit 1
fi

# Chỉ gửi serving config và compiled artifact vào Docker daemon. Source, Git
# metadata và .env không nằm trong build context hoặc layer cache.
tar -cf - \
  web-deployment/Dockerfile \
  web-deployment/nginx.conf \
  web-deployment/nginx-site.conf.template \
  web-deployment/docker-entrypoint.sh \
  build/web |
  docker build --tag "$IMAGE" --file web-deployment/Dockerfile -

printf '%s\n' "✓ Web production image: $IMAGE"
