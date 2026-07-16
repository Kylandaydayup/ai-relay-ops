#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

image="$(ensure_base_image oven/bun:1)"
echo "oven/bun:1 -> $image"
