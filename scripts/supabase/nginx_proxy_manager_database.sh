#!/usr/bin/env bash

# Shared host-side helper for Nginx Proxy Manager database commands. The payload
# resolves the password inside the database container, so the credential never
# crosses the Docker CLI boundary or appears in the host process arguments.

NPM_DATABASE_HELPER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
NPM_DATABASE_EXEC_PAYLOAD=${NPM_DATABASE_EXEC_PAYLOAD:-"$NPM_DATABASE_HELPER_DIR/npm_database_exec_container.sh"}

npm_database_exec() {
  local container=${1:-}
  shift || true

  if [[ -z "$container" || $# -eq 0 ]]; then
    printf '%s\n' 'npm_database_exec yêu cầu container và command.' >&2
    return 64
  fi
  if [[ ! -r "$NPM_DATABASE_EXEC_PAYLOAD" ]]; then
    printf 'Thiếu NPM database exec payload: %s\n' \
      "$NPM_DATABASE_EXEC_PAYLOAD" >&2
    return 66
  fi

  docker exec --interactive "$container" sh -s -- "$@" \
    <"$NPM_DATABASE_EXEC_PAYLOAD"
}
