#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD_DIR=${1:-$ROOT/build/web}

for command_name in curl node python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu command cho Web runtime smoke: %s\n' "$command_name" >&2
    exit 69
  fi
done

if [[ ! -f "$BUILD_DIR/index.html" || ! -f "$BUILD_DIR/main.dart.js" ]]; then
  printf '%s\n' \
    'Thiếu configured build/web artifact; chạy build release với public config trước.' >&2
  exit 66
fi

chrome_binary=
for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
  if command -v "$candidate" >/dev/null 2>&1; then
    chrome_binary=$(command -v "$candidate")
    break
  fi
done
if [[ -z "$chrome_binary" && -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
  chrome_binary="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
fi
if [[ -z "$chrome_binary" ]]; then
  printf '%s\n' 'Không tìm thấy Chrome/Chromium cho Web runtime smoke.' >&2
  exit 69
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-web-runtime.XXXXXX")
chmod 700 "$tmp_dir"
server_pid=
chrome_pid=

cleanup() {
  if [[ -n "$chrome_pid" ]]; then
    kill "$chrome_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
  fi
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT INT TERM

umask 077
server_port_file="$tmp_dir/server-port"
python3 -u -c '
import functools
import http.server
import pathlib
import sys

handler = functools.partial(
    http.server.SimpleHTTPRequestHandler,
    directory=sys.argv[1],
)
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
pathlib.Path(sys.argv[2]).write_text(str(server.server_port), encoding="ascii")
server.serve_forever()
' "$BUILD_DIR" "$server_port_file" \
  >"$tmp_dir/server.log" 2>&1 &
server_pid=$!

server_ready=false
for _ in {1..40}; do
  if [[ ! -s "$server_port_file" ]]; then
    sleep 0.25
    continue
  fi
  server_port=$(<"$server_port_file")
  if curl --silent --fail --max-time 2 \
    "http://127.0.0.1:$server_port/" >/dev/null; then
    server_ready=true
    break
  fi
  sleep 0.25
done
if [[ "$server_ready" != true ]]; then
  printf '%s\n' 'Static server không sẵn sàng cho Web runtime smoke.' >&2
  exit 1
fi

"$chrome_binary" \
  --headless=new \
  --disable-background-networking \
  --disable-default-apps \
  --disable-dev-shm-usage \
  --disable-extensions \
  --disable-gpu \
  --no-first-run \
  --no-sandbox \
  --remote-allow-origins='*' \
  --remote-debugging-port=0 \
  --user-data-dir="$tmp_dir/chrome-profile" \
  "http://127.0.0.1:$server_port/" \
  >"$tmp_dir/chrome.log" 2>&1 &
chrome_pid=$!

devtools_port_file="$tmp_dir/chrome-profile/DevToolsActivePort"
for _ in {1..40}; do
  if [[ -s "$devtools_port_file" ]]; then
    debug_port=$(head -n 1 "$devtools_port_file")
    break
  fi
  sleep 0.25
done
if [[ -z "${debug_port:-}" || ! "$debug_port" =~ ^[0-9]+$ ]]; then
  printf '%s\n' 'Chrome không công bố DevTools port hợp lệ.' >&2
  exit 1
fi

node "$ROOT/tool/agent/web_runtime_probe.mjs" \
  "http://127.0.0.1:$debug_port" \
  "http://127.0.0.1:$server_port/"
