#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

image="$(ensure_new_api_runtime "$(require_base_image debian:bookworm-slim)")"
echo "new-api-runtime -> $image"
