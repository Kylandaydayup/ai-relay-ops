#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$OPS_ROOT/scripts/lib/timing.sh"
start_script_timer "${0##*/}"

config_file="${BUILD_ENV_FILE:-$OPS_ROOT/config/build.env}"
if [ -f "$config_file" ]; then
  # shellcheck disable=SC1090
  . "$config_file"
fi

dry_run=1
if [ "${CLEANUP_CONFIRM:-0}" = "1" ]; then
  dry_run=0
fi

run_or_print() {
  if [ "$dry_run" = "1" ]; then
    printf '[dry-run] %q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

keep_count="${PACKAGE_KEEP_COUNT:-10}"
cache_keep="${DOCKER_CACHE_KEEP:-168h}"
package_dir="${BUILD_PACKAGE_DIR:-${BUILD_ROOT:-$OPS_ROOT/.build}/packages}"

echo "cleanup mode: $([ "$dry_run" = "1" ] && echo dry-run || echo execute)"
df -h "${BUILD_ROOT:-$OPS_ROOT}" || true
docker system df || true

run_or_print docker container prune -f
run_or_print docker image prune -f
run_or_print docker builder prune -f --filter "until=$cache_keep"

if [ -d "$package_dir" ]; then
  find "$package_dir" -maxdepth 1 -type f -name 'edream-platform-*.tar.gz' \
    | sort -r \
    | awk -v keep="$keep_count" 'NR > keep { print }' \
    | while IFS= read -r file; do
        case "$file" in
          */edream-platform-current.tar.gz) continue ;;
        esac
        run_or_print rm -f "$file"
      done
  find "$package_dir" -maxdepth 1 -type f -name 'edream-platform-images-*.tar' \
    | sort -r \
    | awk -v keep="$keep_count" 'NR > keep { print }' \
    | while IFS= read -r file; do
        case "$file" in
          */edream-platform-images-current.tar) continue ;;
        esac
        run_or_print rm -f "$file"
      done
  find "$package_dir" -maxdepth 1 -type f -name 'edream-platform-images-*.txt' \
    | sort -r \
    | awk -v keep="$keep_count" 'NR > keep { print }' \
    | while IFS= read -r file; do
        case "$file" in
          */edream-platform-images-current.txt) continue ;;
        esac
        run_or_print rm -f "$file"
      done
fi

docker system df || true
