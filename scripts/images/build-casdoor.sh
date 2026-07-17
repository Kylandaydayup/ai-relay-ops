#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${CASDOOR_LOCAL_DIR:-../casdoor}")"
image="$(runtime_image_ref casdoor "$source_dir")"
casdoor_web_base="$(require_base_image node:20.20.1)"
casdoor_go_base="$(require_base_image golang:1.25.8)"
casdoor_runtime="$(require_base_image debian:latest)"

push_image "$source_dir" "$OPS_ROOT/docker/casdoor/Dockerfile" "$image" \
  --build-arg "NODE_BASE_IMAGE=$casdoor_web_base" \
  --build-arg "GO_BASE_IMAGE=$casdoor_go_base" \
  --build-arg "RUNTIME_BASE_IMAGE=$casdoor_runtime" \
  --build-arg "GO_PROXY=${GO_PROXY:-https://goproxy.cn,direct}"

write_component_image "casdoor.image" "$image"
