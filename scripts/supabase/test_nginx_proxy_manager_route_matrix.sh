#!/usr/bin/env bash
set -euo pipefail

CRITICAL_MANIFEST=${1:-}
EXCEPTION_MANIFEST=${2:--}
CONFIRMATION=${3:-}
DB_CONTAINER=${NPM_DB_CONTAINER:-nginx-proxy-manager-db}

if [[ -z "$CRITICAL_MANIFEST" ||
  "$CONFIRMATION" != '--allow-production-nginx-proxy-manager-route-probe' ]]; then
  printf '%s\n' \
    'Usage: test_nginx_proxy_manager_route_matrix.sh CRITICAL_MANIFEST EXCEPTION_MANIFEST|- --allow-production-nginx-proxy-manager-route-probe' >&2
  exit 64
fi
if [[ $(uname -s) != Linux ]]; then
  printf '%s\n' 'NPM route matrix chỉ chạy trên Linux operator host.' >&2
  exit 65
fi
for command_name in awk curl docker find grep jq mktemp sed sha256sum sort stat; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Thiếu NPM route-matrix dependency: %s\n' "$command_name" >&2
    exit 69
  fi
done
if [[ ! -f "$CRITICAL_MANIFEST" ]]; then
  printf 'Thiếu NPM critical-route manifest: %s\n' "$CRITICAL_MANIFEST" >&2
  exit 66
fi
manifest_mode=$(stat -c '%a' "$CRITICAL_MANIFEST")
if ((8#$manifest_mode & 8#077)); then
  printf 'NPM critical-route manifest phải private: %s.\n' "$manifest_mode" >&2
  exit 78
fi
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  if [[ ! -f "$EXCEPTION_MANIFEST" ]]; then
    printf 'Thiếu NPM route-exception manifest: %s\n' "$EXCEPTION_MANIFEST" >&2
    exit 66
  fi
  exception_mode=$(stat -c '%a' "$EXCEPTION_MANIFEST")
  if ((8#$exception_mode & 8#077)); then
    printf 'NPM route-exception manifest phải private: %s.\n' \
      "$exception_mode" >&2
    exit 78
  fi
fi
if [[ $(docker inspect "$DB_CONTAINER" --format '{{.State.Running}}') != true ]]; then
  printf '%s\n' 'NPM database container không chạy.' >&2
  exit 1
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hyper-auth-npm-routes.XXXXXX")
chmod 0700 "$tmp_dir"
cleanup() {
  find "$tmp_dir" -depth -delete
}
trap cleanup EXIT
domains_file="$tmp_dir/domains"
domain_ids_file="$tmp_dir/domain-ids"
exceptions_file="$tmp_dir/exceptions"
: >"$exceptions_file"

docker exec "$DB_CONTAINER" sh -lc '
  MYSQL_PWD="$MYSQL_PASSWORD" mariadb \
    --user="$MYSQL_USER" \
    --database="$MYSQL_DATABASE" \
    --batch --skip-column-names \
    --execute="SELECT domain_names FROM proxy_host
                 WHERE enabled=1 AND is_deleted=0
               UNION ALL
               SELECT domain_names FROM redirection_host
                 WHERE enabled=1 AND is_deleted=0
               UNION ALL
               SELECT domain_names FROM dead_host
                 WHERE enabled=1 AND is_deleted=0;"
' | while IFS= read -r domain_json; do
  jq -er '.[] | strings' <<<"$domain_json"
done | LC_ALL=C sort -u >"$domains_file"

domain_count=$(awk 'END {print NR}' "$domains_file")
if [[ ! "$domain_count" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' 'NPM route matrix không tìm thấy enabled HTTP domain.' >&2
  exit 1
fi
if grep -Eq '(^|\.)\*($|\.)' "$domains_file"; then
  printf '%s\n' 'NPM route matrix từ chối wildcard domain; cần representative route.' >&2
  exit 1
fi
if grep -Evq '^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$' "$domains_file"; then
  printf '%s\n' 'NPM route matrix có hostname không hợp lệ.' >&2
  exit 1
fi
while IFS= read -r domain; do
  printf '%s\n' "$(printf '%s' "$domain" | sha256sum | awk '{print substr($1,1,12)}')"
done <"$domains_file" | LC_ALL=C sort -u >"$domain_ids_file"

exception_count=0
if [[ "$EXCEPTION_MANIFEST" != '-' ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%%#*}
    line=$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$line")
    [[ -z "$line" ]] && continue
    read -r exception_status exception_id extra <<<"$line"
    if [[ -n "${extra:-}" || ! "$exception_status" =~ ^5[0-9]{2}$ ||
      ! "$exception_id" =~ ^[0-9a-f]{12}$ ]]; then
      printf '%s\n' 'NPM route-exception manifest có dòng không hợp lệ.' >&2
      exit 64
    fi
    if grep -Eq "^[0-9]{3} ${exception_id}$" "$exceptions_file"; then
      printf '%s\n' 'NPM route-exception manifest có route hash trùng.' >&2
      exit 64
    fi
    if ! grep -Fxq "$exception_id" "$domain_ids_file"; then
      printf '%s\n' 'NPM route exception không thuộc enabled domain hiện tại.' >&2
      exit 1
    fi
    printf '%s %s\n' "$exception_status" "$exception_id" >>"$exceptions_file"
    exception_count=$((exception_count + 1))
  done <"$EXCEPTION_MANIFEST"
fi

stream_count=$(docker exec "$DB_CONTAINER" sh -lc '
  MYSQL_PWD="$MYSQL_PASSWORD" mariadb \
    --user="$MYSQL_USER" \
    --database="$MYSQL_DATABASE" \
    --batch --skip-column-names \
    --execute="SELECT COUNT(*) FROM stream WHERE enabled=1 AND is_deleted=0;"
')
if [[ "$stream_count" != 0 ]]; then
  printf 'NPM route matrix chưa bao phủ %s enabled stream route.\n' \
    "$stream_count" >&2
  exit 1
fi

critical_count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%%#*}
  line=$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$line")
  [[ -z "$line" ]] && continue
  read -r expected_status url extra <<<"$line"
  if [[ -n "${extra:-}" || ! "$expected_status" =~ ^[1-5][0-9]{2}$ ||
    ! "$url" =~ ^https://[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9](/[A-Za-z0-9._~!$%&()*+,;=:@/-]*)?$ ||
    "$url" == *'@'* || "$url" == *'?'* || "$url" == *'#'* ]]; then
    printf '%s\n' 'NPM critical-route manifest có dòng không hợp lệ.' >&2
    exit 64
  fi
  manifest_host=${url#https://}
  manifest_host=${manifest_host%%/*}
  if ! grep -Fxq "$manifest_host" "$domains_file"; then
    printf '%s\n' 'NPM critical route không thuộc enabled NPM domain.' >&2
    exit 1
  fi
  critical_count=$((critical_count + 1))
  route_id=$(printf '%s' "$url" | sha256sum | awk '{print substr($1,1,12)}')
  actual_status=$(curl --silent --show-error \
    --connect-timeout 10 --max-time 20 \
    --output /dev/null --write-out '%{http_code}' "$url" || true)
  if [[ "$actual_status" != "$expected_status" ]]; then
    printf 'NPM critical route fail: id=%s expected=%s actual=%s.\n' \
      "$route_id" "$expected_status" "${actual_status:-000}" >&2
    exit 1
  fi
done <"$CRITICAL_MANIFEST"
if ((critical_count == 0)); then
  printf '%s\n' 'NPM critical-route manifest không có route.' >&2
  exit 64
fi

generic_failures=0
matched_exceptions=0
while IFS= read -r domain; do
  route_id=$(printf '%s' "$domain" | sha256sum | awk '{print substr($1,1,12)}')
  status=$(curl --silent --show-error --location --max-redirs 5 \
    --connect-timeout 10 --max-time 20 \
    --output /dev/null --write-out '%{http_code}' "https://$domain/" || true)
  if [[ "$status" =~ ^[1-4][0-9]{2}$ ]]; then
    continue
  fi
  if grep -Fxq "${status:-000} $route_id" "$exceptions_file"; then
    matched_exceptions=$((matched_exceptions + 1))
  else
    printf 'NPM discovered route fail: id=%s status=%s.\n' \
      "$route_id" "${status:-000}" >&2
    generic_failures=$((generic_failures + 1))
  fi
done <"$domains_file"
if ((generic_failures != 0)); then
  printf 'NPM route matrix fail: %s/%s discovered route lỗi.\n' \
    "$generic_failures" "$domain_count" >&2
  exit 1
fi
if ((matched_exceptions != exception_count)); then
  printf 'NPM route matrix fail: %s/%s exception còn khớp; baseline đã stale.\n' \
    "$matched_exceptions" "$exception_count" >&2
  exit 1
fi

printf 'NPM route matrix pass: %s discovered HTTPS domain, %s critical route, %s/%s matched exception, 0 stream.\n' \
  "$domain_count" "$critical_count" "$matched_exceptions" "$exception_count"
printf '%s\n' 'Output chỉ dùng route hash khi fail; không in hostname hoặc URL.'
