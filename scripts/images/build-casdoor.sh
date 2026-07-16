#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${CASDOOR_LOCAL_DIR:-../casdoor}")"
image="$(runtime_image_ref casdoor "$source_dir")"
node_base="$(ensure_base_image node:20.20.1)"
go_base="$(ensure_base_image golang:1.25.8)"
alpine_base="$(ensure_base_image alpine:latest)"
debian_base="$(ensure_base_image debian:latest)"

push_image "$source_dir" "$OPS_ROOT/docker/casdoor/Dockerfile" "$image" \
  --build-arg "NODE_BASE_IMAGE=$node_base" \
  --build-arg "GO_BASE_IMAGE=$go_base" \
  --build-arg "ALPINE_BASE_IMAGE=$alpine_base" \
  --build-arg "DEBIAN_BASE_IMAGE=$debian_base"

write_component_image "casdoor.image" "$image"
