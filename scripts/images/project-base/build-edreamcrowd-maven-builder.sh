#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${EDREAMCROWD_LOCAL_DIR:-../EDreamCrowd}")"
image="$(ensure_edreamcrowd_maven_builder "$source_dir" "$(require_base_image maven:3.9.9-eclipse-temurin-21)")"
echo "edreamcrowd-maven-builder -> $image"
