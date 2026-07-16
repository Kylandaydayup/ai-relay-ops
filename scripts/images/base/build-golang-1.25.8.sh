#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

image="$(ensure_base_image golang:1.25.8)"
echo "golang:1.25.8 -> $image"
