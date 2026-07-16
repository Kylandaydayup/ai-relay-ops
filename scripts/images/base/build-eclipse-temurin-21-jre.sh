#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

image="$(ensure_base_image eclipse-temurin:21-jre)"
echo "eclipse-temurin:21-jre -> $image"
