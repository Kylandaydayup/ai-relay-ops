#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${BROKER_LOCAL_DIR:-../ai-relay-broker}")"
image="$(runtime_image_ref ai-provider-adapter "$source_dir")"
python_service_base="$(require_base_image python:3.12-slim)"

push_image "$source_dir" "$OPS_ROOT/docker/ai-relay-broker/ai-provider-adapter.Dockerfile" "$image" \
  --build-arg "PYTHON_BASE_IMAGE=$python_service_base" \
  --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

write_component_image "ai-provider-adapter.image" "$image"
