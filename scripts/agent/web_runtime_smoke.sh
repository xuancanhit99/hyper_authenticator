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
  local exit_code=$?
  trap - EXIT
  if [[ -n "$chrome_pid" ]]; then
    kill "$chrome_pid" >/dev/null 2>&1 || true
    wait "$chrome_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$tmp_dir" >/dev/null 2>&1 || true
  return "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

# Chrome trên GitHub-hosted Ubuntu không luôn ghi DevToolsActivePort khi nhận
# port 0. Chọn một loopback port trống ngay trước khi launch và probe readiness;
# không dùng một fixed port có thể xung đột giữa các runner/process.
debug_port=$(python3 -c \
  'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')

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
  --remote-debugging-port="$debug_port" \
  --user-data-dir="$tmp_dir/chrome-profile" \
  "http://127.0.0.1:$server_port/" \
  >"$tmp_dir/chrome.log" 2>&1 &
chrome_pid=$!

devtools_ready=false
for _ in {1..120}; do
  if curl --silent --fail --max-time 1 \
    "http://127.0.0.1:$debug_port/json/version" >/dev/null; then
    devtools_ready=true
    break
  fi
  if ! kill -0 "$chrome_pid" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
if [[ "$devtools_ready" != true ]]; then
  chrome_state=stopped
  log_endpoint_state=missing
  kill -0 "$chrome_pid" >/dev/null 2>&1 && chrome_state=running
  grep -q 'DevTools listening on ws://' "$tmp_dir/chrome.log" && \
    log_endpoint_state=present
  printf \
    'Chrome DevTools không sẵn sàng: process=%s, log_endpoint=%s.\n' \
    "$chrome_state" "$log_endpoint_state" >&2
  exit 1
fi

node "$ROOT/tool/agent/web_runtime_probe.mjs" \
  "http://127.0.0.1:$debug_port" \
  "http://127.0.0.1:$server_port/"
