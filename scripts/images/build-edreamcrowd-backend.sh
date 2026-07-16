#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${EDREAMCROWD_LOCAL_DIR:-../EDreamCrowd}")"
image="$(runtime_image_ref edreamcrowd-backend "$source_dir")"
maven_base="$(ensure_base_image maven:3.9.9-eclipse-temurin-21)"
runtime_base="$(ensure_base_image eclipse-temurin:21-jre)"

push_image "$source_dir" "$source_dir/Dockerfile" "$image" \
  --build-arg "MAVEN_BASE_IMAGE=$maven_base" \
  --build-arg "RUNTIME_BASE_IMAGE=$runtime_base"

write_component_image "edreamcrowd.backend.image" "$image"
