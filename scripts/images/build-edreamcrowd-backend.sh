#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${EDREAMCROWD_LOCAL_DIR:-../EDreamCrowd}")"
image="$(runtime_image_ref edreamcrowd-backend "$source_dir")"
runtime_base="$(require_base_image eclipse-temurin:21-jre)"
edreamcrowd_maven_base="$(require_base_image maven:3.9.9-eclipse-temurin-21)"

push_image "$source_dir" "$OPS_ROOT/docker/edreamcrowd/backend.Dockerfile" "$image" \
  --build-arg "MAVEN_BASE_IMAGE=$edreamcrowd_maven_base" \
  --build-arg "RUNTIME_BASE_IMAGE=$runtime_base" \
  --build-arg "MAVEN_MIRROR_URL=${MAVEN_MIRROR_URL:-https://maven.aliyun.com/repository/public}"

write_component_image "edreamcrowd.backend.image" "$image"
