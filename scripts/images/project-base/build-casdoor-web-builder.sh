#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${CASDOOR_LOCAL_DIR:-../casdoor}")"
image="$(ensure_casdoor_web_builder "$source_dir" "$(require_base_image node:20.20.1)")"
echo "casdoor-web-builder -> $image"
