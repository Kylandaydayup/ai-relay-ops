#!/usr/bin/env bash
set -euo pipefail

env_file="${HARBOR_ENV_FILE:-build/harbor.env}"
if [ -f "$env_file" ]; then
  # shellcheck disable=SC1090
  . "$env_file"
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
