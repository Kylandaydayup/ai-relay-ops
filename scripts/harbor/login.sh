#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$repo_root/scripts/lib/timing.sh"
start_script_timer "${0##*/}"
config_file="${BUILD_ENV_FILE:-$repo_root/config/build.env}"
if [ -f "$config_file" ]; then
  # shellcheck disable=SC1090
  . "$config_file"
fi

registry="${HARBOR_REGISTRY:-}"
username="${HARBOR_USERNAME:?HARBOR_USERNAME is required}"
password="${HARBOR_PASSWORD:?HARBOR_PASSWORD is required}"

if [ -z "${registry:-}" ]; then
  registry="${HARBOR_HOST:?HARBOR_HOST is required}"
  if [ -n "${HARBOR_PORT:-}" ] && [ "$HARBOR_PORT" != "80" ]; then
    registry="${registry}:${HARBOR_PORT}"
  fi
fi

echo "$password" | docker login "$registry" -u "$username" --password-stdin
