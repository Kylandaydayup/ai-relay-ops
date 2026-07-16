#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${CASDOOR_LOCAL_DIR:-../casdoor}")"
image="$(runtime_image_ref casdoor "$source_dir")"
casdoor_web_base="$(require_project_base_image casdoor-web-builder)"
casdoor_go_base="$(require_project_base_image casdoor-go-builder)"
casdoor_runtime="$(require_project_base_image casdoor-runtime)"

push_runtime_image "$source_dir" "$OPS_ROOT/docker/casdoor/Dockerfile" "$image" \
  --build-arg "NODE_BASE_IMAGE=$casdoor_web_base" \
  --build-arg "GO_BASE_IMAGE=$casdoor_go_base" \
  --build-arg "RUNTIME_BASE_IMAGE=$casdoor_runtime"

write_component_image "casdoor.image" "$image"
