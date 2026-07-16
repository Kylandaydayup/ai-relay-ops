#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: sync-base-images.sh <134|139>}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

targets="${BASE_IMAGE_TARGETS:-bun-1 golang-1.26.1-alpine golang-1.25.8 debian-bookworm-slim debian-latest python-3.12-slim maven-3.9.9-eclipse-temurin-21 eclipse-temurin-21-jre node-20-alpine node-20.20.1 nginx-alpine postgres-16-alpine alpine-latest}"

for target in $targets; do
  script="$script_dir/base/build-${target}.sh"
  if [ ! -x "$script" ]; then
    echo "unknown base image target: $target" >&2
    echo "expected executable script: $script" >&2
    exit 2
  fi
  "$script" "$env_name"
done
