#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${EDREAMCROWD_LOCAL_DIR:-../EDreamCrowd}")"
context="$source_dir/frontend"
image="$(runtime_image_ref edreamcrowd-frontend "$source_dir")"
nginx_base="$(require_base_image nginx:alpine)"
edreamcrowd_node_base="$(require_base_image node:20-alpine)"

push_image "$context" "$OPS_ROOT/docker/edreamcrowd/frontend.Dockerfile" "$image" \
  --build-arg "NODE_BASE_IMAGE=$edreamcrowd_node_base" \
  --build-arg "NGINX_BASE_IMAGE=$nginx_base" \
  --build-arg "VITE_PUBLIC_BASE=${VITE_PUBLIC_BASE:-/}"

write_component_image "edreamcrowd.frontend.image" "$image"
