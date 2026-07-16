#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-image-build.sh"
init_image_build "$@"

source_dir="$(abs_path "${BROKER_LOCAL_DIR:-../ai-relay-broker}")"
image="$(ensure_python_service_runtime "$source_dir" "$(require_base_image python:3.12-slim)")"
echo "python-service-runtime -> $image"
