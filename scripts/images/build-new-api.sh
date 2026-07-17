#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${NEW_API_LOCAL_DIR:-../new-api}")"
image="$(runtime_image_ref relay-new-api "$source_dir")"
new_api_bun_base="$(require_base_image oven/bun:1)"
new_api_go_base="$(require_base_image golang:1.26.1-alpine)"
new_api_runtime="$(require_base_image debian:bookworm-slim)"

push_image "$source_dir" "$OPS_ROOT/docker/new-api/Dockerfile" "$image" \
  --build-arg "BUN_BASE_IMAGE=$new_api_bun_base" \
  --build-arg "GO_BASE_IMAGE=$new_api_go_base" \
  --build-arg "RUNTIME_BASE_IMAGE=$new_api_runtime" \
  --build-arg "GO_PROXY=${GO_PROXY:-https://goproxy.cn,direct}"

write_component_image "new-api.image" "$image"
