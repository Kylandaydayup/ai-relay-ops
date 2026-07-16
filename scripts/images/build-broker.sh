#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${BROKER_LOCAL_DIR:-../ai-relay-broker}")"
image="$(runtime_image_ref relay-broker "$source_dir")"
python_base="$(ensure_base_image python:3.12-slim)"

push_image "$source_dir" "$OPS_ROOT/docker/ai-relay-broker/broker.Dockerfile" "$image" \
  --build-arg "PYTHON_BASE_IMAGE=$python_base" \
  --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

write_component_image "broker.image" "$image"
