#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_name="${ENV_NAME:-template}"
build_env_file="${BUILD_ENV_FILE:-build/images.env}"
build_images="${BUILD_IMAGES:-true}"
include_images="${INCLUDE_IMAGES:-true}"
archive="${ARCHIVE:-true}"

cd "$repo_root"

if [ "$build_images" = "true" ]; then
  scripts/build-platform-images.sh "$build_env_file"
fi

ENV_NAME="$env_name" \
INCLUDE_IMAGES="$include_images" \
ARCHIVE="$archive" \
scripts/package-platform-bundle.sh
