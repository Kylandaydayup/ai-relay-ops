#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: build-project-base-images.sh <134|139>}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

targets="${BASE_IMAGE_TARGETS:-python-service-runtime casdoor-web-builder casdoor-go-builder casdoor-runtime new-api-bun-builder new-api-go-builder new-api-runtime edreamcrowd-maven-builder edreamcrowd-node-builder}"

for target in $targets; do
  script="$script_dir/project-base/build-${target}.sh"
  if [ ! -x "$script" ]; then
    echo "unknown project base image target: $target" >&2
    echo "expected executable script: $script" >&2
    exit 2
  fi
  "$script" "$env_name"
done
