#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
edream_repo="${EDREAMCROWD_REPO_ROOT:-/root/EDreamCrowd}"
frontend_tag="${EDREAMCROWD_FRONTEND_IMAGE_TAG:-staging-139-v4}"
backend_tag="${EDREAMCROWD_BACKEND_IMAGE_TAG:-staging-139}"
build_frontend="${BUILD_FRONTEND:-true}"
build_backend="${BUILD_BACKEND:-false}"
node_image="${NODE_BASE_IMAGE:-www.nexushome.top/base-images/node:20-alpine}"
nginx_image="${NGINX_BASE_IMAGE:-www.nexushome.top/base-images/nginx:alpine}"
maven_image="${MAVEN_BASE_IMAGE:-www.nexushome.top/base-images/maven:3.9.9-eclipse-temurin-21}"
runtime_image="${RUNTIME_BASE_IMAGE:-www.nexushome.top/base-images/eclipse-temurin:21-jre}"

if [ ! -d "$edream_repo" ]; then
  echo "missing EDreamCrowd repo: $edream_repo" >&2
  exit 2
fi

import_image() {
  local image=$1
  docker save "$image" | k3s ctr images import -
}

if [ "$build_frontend" = "true" ]; then
  docker build \
    --build-arg NODE_BASE_IMAGE="$node_image" \
    --build-arg NGINX_BASE_IMAGE="$nginx_image" \
    -f "$edream_repo/frontend/Dockerfile" \
    -t "edreamcrowd-frontend:${frontend_tag}" \
    "$edream_repo/frontend"
  import_image "edreamcrowd-frontend:${frontend_tag}"
fi

if [ "$build_backend" = "true" ]; then
  docker build \
    --build-arg MAVEN_BASE_IMAGE="$maven_image" \
    --build-arg RUNTIME_BASE_IMAGE="$runtime_image" \
    -f "$edream_repo/Dockerfile" \
    -t "edreamcrowd-backend:${backend_tag}" \
    "$edream_repo"
  import_image "edreamcrowd-backend:${backend_tag}"
fi
