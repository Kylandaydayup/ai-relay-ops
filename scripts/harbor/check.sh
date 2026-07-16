#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: check.sh <134|139>}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
harbor_file="$repo_root/environments/$env_name/harbor.yaml"

if command -v ruby >/dev/null 2>&1; then
  registry="$(ruby -ryaml -e 'data=YAML.load_file(ARGV[0]); print data.dig("harbor", "registry")' "$harbor_file")"
else
  registry="$(python3 - "$harbor_file" <<'PY'
import sys
import yaml
with open(sys.argv[1], encoding="utf-8") as handle:
    data = yaml.safe_load(handle) or {}
print(data.get("harbor", {}).get("registry", ""), end="")
PY
)"
fi
if [ -z "$registry" ]; then
  echo "missing harbor.registry in $harbor_file" >&2
  exit 2
fi

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

base_url="${HARBOR_SCHEME:-http}://$registry"
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
  200|401)
    ;;
  *)
    echo "Docker registry check failed: $base_url/v2/ returned $registry_status" >&2
    exit 1
    ;;
esac

if [ -n "${HARBOR_CHECK_IMAGE:-}" ]; then
  require_command docker
  docker pull "$registry/$HARBOR_CHECK_IMAGE" >/dev/null
fi

echo "Harbor check passed: env=$env_name registry=$registry health=healthy registry_http=$registry_status"
