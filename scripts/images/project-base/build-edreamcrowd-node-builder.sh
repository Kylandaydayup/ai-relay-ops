#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${EDREAMCROWD_LOCAL_DIR:-../EDreamCrowd}")"
image="$(ensure_edreamcrowd_node_builder "$source_dir" "$(require_base_image node:20-alpine)")"
echo "edreamcrowd-node-builder -> $image"
