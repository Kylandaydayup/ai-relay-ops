#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${NEW_API_LOCAL_DIR:-../new-api}")"
image="$(runtime_image_ref relay-new-api "$source_dir")"
new_api_bun_base="$(require_project_base_image new-api-bun-builder)"
new_api_go_base="$(require_project_base_image new-api-go-builder)"
new_api_runtime="$(require_project_base_image new-api-runtime)"

push_runtime_image "$source_dir" "$OPS_ROOT/docker/new-api/Dockerfile" "$image" \
  --build-arg "BUN_BASE_IMAGE=$new_api_bun_base" \
  --build-arg "GO_BASE_IMAGE=$new_api_go_base" \
  --build-arg "RUNTIME_BASE_IMAGE=$new_api_runtime"

write_component_image "new-api.image" "$image"
