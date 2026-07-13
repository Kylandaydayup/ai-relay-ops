#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${1:-${HARBOR_ENV_FILE:-build/harbor.env}}"

cd "$repo_root"
# shellcheck source=../build/harbor.env.example
. "$env_file"

registry="${HARBOR_REGISTRY:-${HARBOR_HOST}:${HARBOR_PORT}}"
project="${HARBOR_BASE_PROJECT:-base-images}"
images="${BASE_IMAGES:-postgres:16-alpine nginx:alpine node:20-alpine node:22-slim python:3.12-slim debian:bookworm-slim alpine:latest}"

if [ -n "${HARBOR_USERNAME:-}" ] && [ -n "${HARBOR_PASSWORD:-}" ]; then
  echo "$HARBOR_PASSWORD" | docker login "$registry" -u "$HARBOR_USERNAME" --password-stdin
fi

for src in $images; do
  name="${src%%:*}"
  tag="${src##*:}"
  name="${name##*/}"
  dst="${registry}/${project}/${name}:${tag}"
  docker pull "$src"
  docker tag "$src" "$dst"
  docker push "$dst"
  echo "$src -> $dst"
done
