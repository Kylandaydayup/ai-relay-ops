#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${CASDOOR_LOCAL_DIR:-../casdoor}")"
image="$(ensure_casdoor_go_builder "$source_dir" "$(require_base_image golang:1.25.8)")"
echo "casdoor-go-builder -> $image"
