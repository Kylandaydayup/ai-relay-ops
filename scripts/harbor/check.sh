#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$repo_root/scripts/lib/timing.sh"
start_script_timer "${0##*/}"
config_file="${BUILD_ENV_FILE:-$repo_root/config/build.env}"

if [ ! -f "$config_file" ]; then
  echo "missing build config: $config_file" >&2
  exit 2
fi
# shellcheck disable=SC1090
. "$config_file"

registry="${HARBOR_REGISTRY:?HARBOR_REGISTRY is required}"
scheme="${HARBOR_SCHEME:-http}"

require_command() {
  local name=$1
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "missing required command: $name" >&2
    exit 2
  fi
}

http_status() {
  local url=$1
  curl -k -sS -o /tmp/harbor-check-body -w "%{http_code}" "$url"
}

require_command curl

base_url="${scheme}://$registry"
health_status="$(http_status "$base_url/api/v2.0/health")"
if [ "$health_status" != "200" ]; then
  echo "Harbor health check failed: $base_url/api/v2.0/health returned $health_status" >&2
  exit 1
fi

if ! grep -q '"status"[[:space:]]*:[[:space:]]*"healthy"' /tmp/harbor-check-body; then
  echo "Harbor health check failed: status is not healthy" >&2
  exit 1
fi

registry_status="$(http_status "$base_url/v2/" || true)"
case "$registry_status" in
  200|401) ;;
  *)
    echo "Docker registry check failed: $base_url/v2/ returned $registry_status" >&2
    exit 1
    ;;
esac

echo "Harbor check passed: registry=$registry health=healthy registry_http=$registry_status"
