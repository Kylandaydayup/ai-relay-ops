#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${NEW_API_LOCAL_DIR:-../new-api}")"
image="$(ensure_new_api_bun_builder "$source_dir" "$(require_base_image oven/bun:1)")"
echo "new-api-bun-builder -> $image"
