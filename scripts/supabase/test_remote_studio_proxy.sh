#!/usr/bin/env bash
set -euo pipefail

PUBLIC_ORIGIN=${1:-}
STUDIO_CONTAINER=${STUDIO_CONTAINER:-supabase-studio}
PROXY_CONTAINER=${PROXY_CONTAINER:-nginx-proxy-manager-app}

health=$(docker inspect --format '{{.State.Health.Status}}' "$STUDIO_CONTAINER")
[[ "$health" == healthy ]]

networks=$(docker inspect "$STUDIO_CONTAINER" --format '{{json .NetworkSettings.Networks}}')
jq -e 'has("supabase_default") and has("proxy-network")' <<< "$networks" >/dev/null

docker exec "$PROXY_CONTAINER" getent hosts "$STUDIO_CONTAINER" >/dev/null
docker exec "$PROXY_CONTAINER" node -e '
  fetch(`http://${process.argv[1]}:3000/api/platform/profile`)
    .then((response) => {
      if (response.status !== 200) throw new Error(String(response.status));
    })
    .catch((error) => {
      console.error(error.message);
      process.exit(1);
    });
' "$STUDIO_CONTAINER"

if [[ -n "$PUBLIC_ORIGIN" ]]; then
  PUBLIC_ORIGIN=${PUBLIC_ORIGIN%/}
  [[ "$PUBLIC_ORIGIN" == https://* ]]
  public_status=$(curl --connect-timeout 10 --max-time 20 -sS \
    -o /dev/null -w '%{http_code}' "$PUBLIC_ORIGIN/")
  [[ "$public_status" == 401 ]]
fi

printf '%s\n' 'Studio proxy contract pass: healthy, shared network, upstream HTTP và Basic Auth boundary.'
