#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

image="$(ensure_casdoor_runtime "$(require_base_image debian:latest)")"
echo "casdoor-runtime -> $image"
