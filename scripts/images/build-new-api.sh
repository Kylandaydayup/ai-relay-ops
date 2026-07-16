#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${NEW_API_LOCAL_DIR:-../new-api}")"
image="$(runtime_image_ref relay-new-api "$source_dir")"
bun_base="$(ensure_base_image oven/bun:1)"
go_base="$(ensure_base_image golang:1.26.1-alpine)"
runtime_base="$(ensure_base_image debian:bookworm-slim)"

push_image "$source_dir" "$OPS_ROOT/docker/new-api/Dockerfile" "$image" \
  --build-arg "BUN_BASE_IMAGE=$bun_base" \
  --build-arg "GO_BASE_IMAGE=$go_base" \
  --build-arg "RUNTIME_BASE_IMAGE=$runtime_base"

write_component_image "new-api.image" "$image"
