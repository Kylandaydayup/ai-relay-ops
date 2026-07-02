#!/usr/bin/env bash
set -euo pipefail

repo_dir="${BROKER_REPO_DIR:-/root/ai-relay-broker}"
image_tag="${BROKER_IMAGE_TAG:-v0.1.5}"
pip_index_url="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

cd "$repo_dir"

docker build \
  --build-arg PIP_INDEX_URL="$pip_index_url" \
  -t "ai-relay-broker:${image_tag}" \
  .

docker save "ai-relay-broker:${image_tag}" | k3s ctr images import -
