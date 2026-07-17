#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$script_dir/lib-image-build.sh"
init_image_build "$@"

if [ "${BUILD_CASDOOR:-0}" = "1" ]; then
  "$script_dir/build-casdoor.sh"
  exit 0
fi

casdoor_image="${CASDOOR_IMAGE:-}"
if [ -z "$casdoor_image" ] && [ -n "${DEPLOYMENT_VALUES_FILE:-}" ] && [ -f "$DEPLOYMENT_VALUES_FILE" ]; then
  repository="$(yaml_get "$DEPLOYMENT_VALUES_FILE" casdoor.image.repository)"
  tag="$(yaml_get "$DEPLOYMENT_VALUES_FILE" casdoor.image.tag)"
  if [ -n "$repository" ] && [ -n "$tag" ]; then
    casdoor_image="$repository:$tag"
  fi
fi

if [ -n "$casdoor_image" ]; then
  build_image="$(build_image_ref "$casdoor_image")"
  if docker pull --platform "$IMAGE_PLATFORM" "$build_image" >/dev/null 2>&1; then
    write_component_image "casdoor.image" "$build_image"
    echo "casdoor image reused: $(deployment_image_ref "$build_image")"
    exit 0
  fi
  echo "casdoor image not found in Harbor, building it: $casdoor_image" >&2
else
  echo "casdoor image is not configured, building it" >&2
fi

"$script_dir/build-casdoor.sh"
