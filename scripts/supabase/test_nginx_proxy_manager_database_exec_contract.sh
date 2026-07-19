#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LIBRARY="$ROOT/scripts/supabase/nginx_proxy_manager_database.sh"
PAYLOAD="$ROOT/scripts/supabase/npm_database_exec_container.sh"

for path in "$LIBRARY" "$PAYLOAD"; do
  if [[ ! -r "$path" ]]; then
    printf 'Thiếu NPM database credential helper: %s\n' "$path" >&2
    exit 66
  fi
  bash -n "$path"
done

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-npm-db-secret.XXXXXX")
chmod 0700 "$tmp_dir"
cleanup() {
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT

fake_bin="$tmp_dir/bin"
mkdir -m 0700 "$fake_bin"
cat >"$fake_bin/docker" <<'FAKE_DOCKER'
#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != exec || ${2:-} != --interactive || -z ${3:-} ||
  ${4:-} != sh || ${5:-} != -s || ${6:-} != -- ]]; then
  exit 64
fi
shift 6

case ${FAKE_DB_CREDENTIAL_MODE:-} in
  env)
    MYSQL_PASSWORD=TEST_ONLY_ENV_PASSWORD exec sh -s -- "$@"
    ;;
  file)
    MYSQL_PASSWORD_FILE=$FAKE_DB_SECRET_FILE exec sh -s -- "$@"
    ;;
  mariadb-file)
    MARIADB_PASSWORD_FILE=$FAKE_DB_SECRET_FILE exec sh -s -- "$@"
    ;;
  empty)
    exec env -u MYSQL_PASSWORD -u MARIADB_PASSWORD \
      -u MYSQL_PASSWORD_FILE -u MARIADB_PASSWORD_FILE sh -s -- "$@"
    ;;
  *) exit 64 ;;
esac
FAKE_DOCKER
chmod 0700 "$fake_bin/docker"

secret_file="$tmp_dir/database-password"
printf '%s' 'TEST_ONLY_FILE_PASSWORD' >"$secret_file"
chmod 0400 "$secret_file"

# shellcheck source=nginx_proxy_manager_database.sh
source "$LIBRARY"
export PATH="$fake_bin:$PATH"
export FAKE_DB_SECRET_FILE=$secret_file

output=$(
  FAKE_DB_CREDENTIAL_MODE=env npm_database_exec test-db \
    sh -c 'test "$MYSQL_PWD" = TEST_ONLY_ENV_PASSWORD'
)
[[ -z "$output" ]]

for mode in file mariadb-file; do
  output=$(
    FAKE_DB_CREDENTIAL_MODE=$mode npm_database_exec test-db \
      sh -c 'test "$MYSQL_PWD" = TEST_ONLY_FILE_PASSWORD'
  )
  [[ -z "$output" ]]
done

set +e
FAKE_DB_CREDENTIAL_MODE=env npm_database_exec test-db sh -c 'exit 23'
command_status=$?
set -e
if [[ $command_status -ne 23 ]]; then
  printf 'NPM database helper không giữ command exit status: %s.\n' \
    "$command_status" >&2
  exit 1
fi

if FAKE_DB_CREDENTIAL_MODE=empty npm_database_exec test-db true \
  >"$tmp_dir/empty.out" 2>"$tmp_dir/empty.err"; then
  printf '%s\n' 'NPM database helper phải fail khi thiếu credential.' >&2
  exit 1
fi
if [[ -s "$tmp_dir/empty.out" || -s "$tmp_dir/empty.err" ]]; then
  printf '%s\n' 'NPM database helper không được log khi thiếu credential.' >&2
  exit 1
fi

symlink_secret="$tmp_dir/database-password-link"
ln -s "$secret_file" "$symlink_secret"
empty_secret="$tmp_dir/database-password-empty"
: >"$empty_secret"
chmod 0400 "$empty_secret"
for invalid_secret in relative-secret "$symlink_secret" "$empty_secret"; do
  if FAKE_DB_CREDENTIAL_MODE=file FAKE_DB_SECRET_FILE=$invalid_secret \
    npm_database_exec test-db true >"$tmp_dir/invalid.out" \
      2>"$tmp_dir/invalid.err"; then
    printf 'NPM database helper phải từ chối secret không hợp lệ: %s.\n' \
      "$invalid_secret" >&2
    exit 1
  fi
  if [[ -s "$tmp_dir/invalid.out" || -s "$tmp_dir/invalid.err" ]]; then
    printf '%s\n' 'NPM database helper không được log khi secret không hợp lệ.' >&2
    exit 1
  fi
done

if grep -Eq 'set -x|printf.*(database_password|MYSQL_PWD)|echo.*(database_password|MYSQL_PWD)' \
  "$LIBRARY" "$PAYLOAD"; then
  printf '%s\n' 'NPM database helper có đường log credential bị cấm.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM database credential contract pass: env/file fallback, exit propagation và invalid-file silent reject.'
