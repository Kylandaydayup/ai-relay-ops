#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$OPS_ROOT"
image="$(runtime_image_ref platform-gateway "$source_dir")"
nginx_base="$(ensure_base_image nginx:alpine)"

push_image "$OPS_ROOT" "$OPS_ROOT/docker/gateway/Dockerfile" "$image" \
  --build-arg "NGINX_BASE_IMAGE=$nginx_base"

write_component_image "gateway.image" "$image"
