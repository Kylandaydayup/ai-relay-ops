#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

image="$(ensure_base_image maven:3.9.9-eclipse-temurin-21)"
echo "maven:3.9.9-eclipse-temurin-21 -> $image"
