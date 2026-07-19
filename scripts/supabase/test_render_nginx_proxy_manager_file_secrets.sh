#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RENDERER="$ROOT/scripts/supabase/render_nginx_proxy_manager_file_secrets.py"

if [[ ! -x "$RENDERER" ]]; then
  printf 'Thiếu executable NPM file-secret renderer: %s\n' "$RENDERER" >&2
  exit 66
fi
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-npm-secret-render.XXXXXX")
chmod 0700 "$tmp_dir"
cleanup() {
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT

PYTHONPYCACHEPREFIX="$tmp_dir/pycache" python3 -m py_compile "$RENDERER"

resolved="$tmp_dir/resolved.json"
original_env="$tmp_dir/original.env"
cat >"$resolved" <<'JSON'
{
  "name": "npm-test",
  "services": {
    "nginx-proxy-manager-app": {
      "environment": {
        "DB_MYSQL_HOST": "db",
        "DB_MYSQL_NAME": "npm",
        "DB_MYSQL_PASSWORD": "TEST_ONLY_APP_PASSWORD_123",
        "DB_MYSQL_USER": "npm"
      },
      "image": "example.invalid/npm@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    "nginx-proxy-manager-db": {
      "environment": {
        "MYSQL_DATABASE": "npm",
        "MYSQL_PASSWORD": "TEST_ONLY_APP_PASSWORD_123",
        "MYSQL_ROOT_PASSWORD": "TEST_ONLY_ROOT_PASSWORD_456",
        "MYSQL_USER": "npm"
      },
      "image": "example.invalid/mariadb@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  }
}
JSON
cat >"$original_env" <<'ENV'
KEEP_ME=public-value
MYSQL_PASSWORD=TEST_ONLY_APP_PASSWORD_123
MYSQL_ROOT_PASSWORD=TEST_ONLY_ROOT_PASSWORD_456
ENV
chmod 0600 "$resolved" "$original_env"

candidate="$tmp_dir/candidate.yaml"
candidate_env="$tmp_dir/candidate.env"
secrets_dir="$tmp_dir/secrets"
"$RENDERER" "$resolved" "$original_env" "$candidate" "$candidate_env" \
  "$secrets_dir" >"$tmp_dir/render.out"

python3 - "$candidate" "$candidate_env" "$secrets_dir" <<'PY'
import json
import stat
import sys
from pathlib import Path

candidate = Path(sys.argv[1])
candidate_env = Path(sys.argv[2])
secrets = Path(sys.argv[3])
config = json.loads(candidate.read_text())
app = config["services"]["nginx-proxy-manager-app"]
db = config["services"]["nginx-proxy-manager-db"]
assert "DB_MYSQL_PASSWORD" not in app["environment"]
assert app["environment"]["DB_MYSQL_PASSWORD__FILE"] == "/run/secrets/npm_db_password"
assert "MYSQL_PASSWORD" not in db["environment"]
assert "MYSQL_ROOT_PASSWORD" not in db["environment"]
assert db["environment"]["MYSQL_PASSWORD_FILE"] == "/run/secrets/npm_db_password"
assert db["environment"]["MYSQL_ROOT_PASSWORD_FILE"] == "/run/secrets/npm_db_root_password"
assert config["secrets"]["npm_db_password"]["file"] == "./secrets/npm_db_password"
assert candidate_env.read_text() == "KEEP_ME=public-value\n"
assert (secrets / "npm_db_password").read_text() == "TEST_ONLY_APP_PASSWORD_123"
assert (secrets / "npm_db_root_password").read_text() == "TEST_ONLY_ROOT_PASSWORD_456"
for path, mode in ((candidate, 0o600), (candidate_env, 0o600), (secrets, 0o700),
                   (secrets / "npm_db_password", 0o400),
                   (secrets / "npm_db_root_password", 0o400)):
    assert stat.S_IMODE(path.stat().st_mode) == mode
serialized = candidate.read_text() + candidate_env.read_text()
assert "TEST_ONLY_APP_PASSWORD_123" not in serialized
assert "TEST_ONLY_ROOT_PASSWORD_456" not in serialized
PY

python3 - "$resolved" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
config = json.loads(path.read_text())
config["services"]["nginx-proxy-manager-app"]["environment"]["DB_MYSQL_PASSWORD"] = \
    "TEST_ONLY_DIFFERENT_PASSWORD"
path.write_text(json.dumps(config))
PY
invalid_dir="$tmp_dir/invalid"
mkdir -m 0700 "$invalid_dir"
if "$RENDERER" "$resolved" "$original_env" "$invalid_dir/candidate.yaml" \
  "$invalid_dir/candidate.env" "$invalid_dir/secrets" \
  >"$invalid_dir/stdout" 2>"$invalid_dir/stderr"; then
  printf '%s\n' 'NPM renderer phải từ chối app/DB password mismatch.' >&2
  exit 1
fi
if grep -Fq 'TEST_ONLY_' "$invalid_dir/stdout" "$invalid_dir/stderr"; then
  printf '%s\n' 'NPM renderer không được log credential khi fail.' >&2
  exit 1
fi

printf '%s\n' \
  'NPM file-secret renderer contract pass: exact transform, private mode và mismatch redaction.'
